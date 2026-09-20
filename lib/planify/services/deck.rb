# frozen_string_literal: true

module Planify
  module Services
    # core/Services/Deck. Nextcloud Deck maps cleanly onto Planify: a board is
    # a project, a stack is a section, a card is a task. It rides on the same
    # CalDAV account credentials, on the Deck REST API rather than WebDAV.
    module Deck
      module_function

      def store = Store.instance

      def headers = { "OCS-APIRequest" => "true", "Content-Type" => "application/json" }

      def call(source, method, path, body = nil, &callback)
        Http.async(
          method,
          "#{source.deck_base_url}#{path}",
          body:       body.nil? ? nil : JSON.generate(body),
          headers:    headers,
          auth:       WebDAV.credentials(source),
          ignore_ssl: source["ignore_ssl"] == true,
          &callback
        )
      end

      # Whether this Nextcloud has Deck installed at all; the Accounts page
      # only offers the switch when it does.
      def probe(source, &done)
        call(source, "GET", "/boards") do |response|
          done.call(response.ok?)
        end
      end

      def sync(source, &done)
        call(source, "GET", "/boards") do |response|
          if !response.ok?
            LogService.warn("Deck", "boards failed: #{response.message}")
            done&.call
          else
            boards(response).then { |list| sync_boards(source, list, &done) }
          end
        end
      end

      def boards(response)
        response.json.then { |payload| payload.is_a?(Array) ? payload : [] }
                .reject { |board| board["archived"] == true && board["deletedAt"].to_i.positive? }
      end

      def sync_boards(source, list, &done)
        list.each { |board| upsert_board(source, board) }
        prune_boards(source, list)

        remaining = list.dup
        step = nil
        step = lambda do
          if remaining.empty?
            done&.call
          else
            sync_stacks(source, remaining.shift) { step.call }
          end
        end
        step.call
      end

      # Deck ids are integers and would collide with CalDAV's; they are
      # namespaced so both backends can live under one account.
      def project_id(board) = "deck-#{board['id']}"

      def section_id(stack) = "deck-stack-#{stack['id']}"

      def item_id(card) = "deck-card-#{card['id']}"

      def upsert_board(source, board)
        store.project(project_id(board)).then do |project|
          if project.nil?
            store.insert_project(board_to_project(source, board), queue: false)
          else
            store.update_project(assign_board(project, board), queue: false)
          end
        end
      end

      def board_to_project(source, board)
        Project.new(
          id:           project_id(board),
          source_id:    source.id,
          backend_type: "deck",
          view_style:   "board",
        ).tap { |project| assign_board(project, board) }
      end

      def assign_board(project, board)
        project.tap do |record|
          record.name = board["title"].to_s
          record.color = board_color(board, record.color)
          record.is_archived = Record.flag(board["archived"])
          record.sync_id = board["id"].to_s
        end
      end

      # Deck sends a bare hex triplet with no leading hash.
      def board_color(board, fallback)
        board["color"].to_s.then { |value| value.empty? ? fallback : "##{value}" }
      end

      def prune_boards(source, list)
        list.map { |board| project_id(board) }.then do |seen|
          store.projects_by_source(source.id)
               .select { |project| project.backend_type == "deck" }
               .reject { |project| seen.include?(project.id) }
               .each { |project| store.delete_project(project, queue: false) }
        end
      end

      def sync_stacks(source, board, &done)
        call(source, "GET", "/boards/#{board['id']}/stacks") do |response|
          if response.ok?
            (response.json.is_a?(Array) ? response.json : []).then do |stacks|
              stacks.each { |stack| upsert_stack(board, stack) }
              prune_stacks(board, stacks)
            end
          else
            LogService.warn("Deck", "stacks failed: #{response.message}")
          end

          done.call
        end
      end

      def upsert_stack(board, stack)
        store.section(section_id(stack)).then do |section|
          if section.nil?
            store.insert_section(stack_to_section(board, stack), queue: false)
          else
            store.update_section(assign_stack(section, board, stack), queue: false)
          end
        end

        # Stacks carry their cards inline, so there is no second request.
        Array(stack["cards"]).each { |card| upsert_card(board, stack, card) }
        prune_cards(stack, Array(stack["cards"]))
      end

      def stack_to_section(board, stack)
        Section.new(id: section_id(stack)).tap { |section| assign_stack(section, board, stack) }
      end

      def assign_stack(section, board, stack)
        section.tap do |record|
          record.name = stack["title"].to_s
          record.project_id = project_id(board)
          record.section_order = stack["order"].to_i
        end
      end

      def prune_stacks(board, stacks)
        stacks.map { |stack| section_id(stack) }.then do |seen|
          store.sections_by_project(project_id(board))
               .reject { |section| seen.include?(section.id) }
               .each { |section| store.delete_section(section, queue: false) }
        end
      end

      def upsert_card(board, stack, card)
        store.item(item_id(card)).then do |item|
          if item.nil?
            store.insert_item(card_to_item(board, stack, card), queue: false)
          else
            store.update_item(
              assign_card(
                item,
                board,
                stack,
                card,
              ),
              queue: false,
            )
          end
        end
      end

      def card_to_item(board, stack, card)
        Item.new(id: item_id(card)).tap { |item| assign_card(
          item,
          board,
          stack,
          card,
        ) }
      end

      def assign_card(item, board, stack, card)
        item.tap do |record|
          record.content = card["title"].to_s
          record.description = card["description"].to_s
          record.project_id = project_id(board)
          record.section_id = section_id(stack)
          record.child_order = card["order"].to_i
          record.checked = Record.flag(!card["done"].to_s.empty?)
          record.completed_at = card["done"].to_s
          record.due_date = Datetime.parse(card["duedate"])
          record.label_ids = card_labels(card)
        end
      end

      def card_labels(card)
        Array(card["labels"]).filter_map do |label|
          label["title"].to_s.then do |name|
            if name.empty?
              next nil
            end

            store.label_by_name(name).then do |existing|
              if existing.nil?
                store.insert_label(Label.new(name: name, color: Palette.random)).id
              else
                existing.id
              end
            end
          end
        end
      end

      def prune_cards(stack, cards)
        cards.map { |card| item_id(card) }.then do |seen|
          store.items_by_section(section_id(stack))
               .reject { |item| seen.include?(item.id) }
               .each { |item| store.delete_item(item, queue: false) }
        end
      end

      # --- pushing ---------------------------------------------------------

      def card_body(item)
        {
          "title"       => item.content.to_s,
          "description" => item.description.to_s,
          "type"        => "plain",
          "order"       => item.child_order.to_i,
          "duedate"     => item.has_due? ? item.due_date.utc.iso8601 : nil,
        }
      end

      def push_card(source, item, &done)
        deck_ids(item).then do |(board_id, stack_id, card_id)|
          if board_id.nil? || stack_id.nil?
            done.call(false)
          elsif card_id.nil?
            call(

              source,

              "POST",

              "/boards/#{board_id}/stacks/#{stack_id}/cards",
              card_body(item),
            ) { |response| done.call(response.ok?) }
          else
            call(

              source,

              "PUT",

              "/boards/#{board_id}/stacks/#{stack_id}/cards/#{card_id}",
              card_body(item),
            ) { |response| done.call(response.ok?) }
          end
        end
      end

      def deck_ids(item)
        [
          store.project(item.project_id)&.sync_id,
          item.section_id.to_s.delete_prefix("deck-stack-").then { |v| v.empty? ? nil : v },
          item.id.to_s.start_with?("deck-card-") ? item.id.delete_prefix("deck-card-") : nil,
        ]
      end

      def delete_card(source, item, &done)
        deck_ids(item).then do |(board_id, stack_id, card_id)|
          if board_id.nil? || stack_id.nil? || card_id.nil?
            done.call(false)
          else
            call(source, "DELETE", "/boards/#{board_id}/stacks/#{stack_id}/cards/#{card_id}") do |response|
              done.call(response.ok?)
            end
          end
        end
      end
    end
  end
end
