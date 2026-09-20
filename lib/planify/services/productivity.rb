# frozen_string_literal: true

module Planify
  module Services
    # src/Services/ProductivityService.vala. Counts of completed tasks against
    # the goals, plus the streak and heat-map data the report draws.
    module Productivity
      module_function

      def store = Store.instance

      def stats
        {
          completed_today: completed_on(Date.today).size,
          completed_week:  completed_between(week_start, Date.today).size,
          completed_month: completed_between(month_start, Date.today).size,
          daily_goal:      daily_goal,
          weekly_goal:     weekly_goal,
          daily_progress:  progress(completed_on(Date.today).size, daily_goal),
          weekly_progress: progress(completed_between(week_start, Date.today).size, weekly_goal),
          streak:          streak,
        }
      end

      def progress(done, goal) = goal.positive? ? done.to_f / goal : 0.0

      def completed
        store.items.select { |item| item.checked? && !item.completed_at.to_s.empty? }
      end

      def completed_on(date)
        completed.select { |item| completed_date(item) == date }
      end

      def completed_between(from, to)
        completed.select do |item|
          completed_date(item).then { |date| !date.nil? && date >= from && date <= to }
        end
      end

      def completed_date(item)
        Datetime.parse(item.completed_at)&.to_date
      end

      # A dynamic goal is "what was actually on the plate", so it moves with
      # the work rather than with a number set once in preferences.
      def dynamic? = Settings.get_boolean("use-dynamic-goal")

      def daily_goal
        if dynamic?
          store.items.count { |item| Datetime.same_day?(item.due_date, Time.now) }
        else
          Settings.get_int("daily-task-goal")
        end
      end

      def weekly_goal
        if dynamic?
          store.items.count do |item|
            item.due_date.then do |due|
              !due.nil? && due.to_date >= week_start && due.to_date <= Date.today
            end
          end
        else
          Settings.get_int("weekly-task-goal")
        end
      end

      def goals? = dynamic? || daily_goal.positive? || weekly_goal.positive?

      # "start-week" is 0 for Sunday through 6 for Saturday.
      def week_start(date = Date.today)
        Settings.get_enum("start-week").then do |configured|
          if configured.zero?
            target = 7
          else
            target = configured
          end
          current = date.cwday
          ((current - target) % 7).then { |diff| date - diff }
        end
      end

      def month_start(date = Date.today) = Date.new(date.year, date.month, 1)

      # Consecutive days, counting back, on which something was completed.
      # Today having nothing yet does not break a live streak, so the count
      # starts at yesterday when today is empty.
      def streak
        counts_by_date.then do |counts|
          if counts.key?(Date.today)
            start = Date.today
          else
            start = Date.today - 1
          end

          run = 0
          date = start

          while counts.key?(date)
            run += 1
            date -= 1
          end

          run
        end
      end

      def counts_by_date
        Hash.new(0).tap do |counts|
          completed.each do |item|
            completed_date(item).then do |date|
              unless date.nil?
                counts[date] += 1
              end
            end
          end
        end
      end

      # The heat map wants one cell per day for the last year.
      def heatmap(days = 365)
        counts_by_date.then do |counts|
          ((Date.today - (days - 1))..Date.today).map do |date|
            { date: date, count: counts[date] }
          end
        end
      end

      def busiest_day
        counts_by_date.max_by { |_, count| count }
      end

      def per_project
        completed.group_by(&:project_id)
                 .map { |id, items| [store.project(id)&.name.to_s, items.size] }
                 .reject { |(name, _)| name.empty? }
                 .sort_by { |(_, count)| -count }
      end

      def watch
        %i[item_updated item_added item_deleted].each do |event|
          store.on(event, owner: self) { EventBus.emit(:stats_changed) }
        end

        %w[daily-task-goal weekly-task-goal use-dynamic-goal].each do |key|
          Settings.changed(key) { EventBus.emit(:stats_changed) }
        end
      end
    end
  end
end
