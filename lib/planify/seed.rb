# frozen_string_literal: true

module Planify
  # Util.create_inbox_project / create_tutorial_project / create_default_labels.
  # The tutorial project is recreatable from Preferences, so it lives here
  # rather than inline in the first-run path.
  module Seed
    module_function

    def install(store)
      create_inbox(store)
      create_tutorial(store)
      create_default_labels(store)
    end

    def create_inbox(store)
      Project.new(
        name:          _("Inbox"),
        inbox_project: 1,
        color:         "blue",
        source_id:     "local",
      ).tap do |project|
        store.insert_project(project)
        Settings.set_string("local-inbox-project-id", project.id)
      end
    end

    def create_tutorial(store)
      Project.new(
        name:           _("Meet Planify"),
        color:          "blue",
        icon_style:     "emoji",
        emoji:          "🚀️",
        show_completed: 1,
        source_id:      "local",
        description:    _(
          "This project shows you everything you need to know to hit the " \
                                    "ground running. Don’t hesitate to play around with it – you can " \
                                    "always recreate it from Preferences.",
        ),
      ).tap do |project|
        store.insert_project(project)
        tutorial_items(project).each_with_index do |(content, description), index|
          store.insert_item(
            Item.new(
              project_id:  project.id,
              content:     content,
              description: description,
              child_order: index,
            ),
          )
        end

        tutorial_sections(project).each_with_index do |(name, items), index|
          Section.new(name: name, project_id: project.id, section_order: index).tap do |section|
            store.insert_section(section)
            items.each_with_index do |(content, description), item_index|
              store.insert_item(
                Item.new(
                  project_id:  project.id,
                  section_id:  section.id,
                  content:     content,
                  description: description,
                  child_order: item_index,
                ),
              )
            end
          end
        end
      end
    end

    def tutorial_items(_project)
      [
        [_("Tap this task"),
         _("You're looking at a to-do! Complete it by tapping the checkbox on the left. ")
],
        [_("Create a new task"),
         _(
           "Now it's your turn! Tap the '+' button at the bottom of your project, enter a " \
                      "task description, and tap the 'Add Task' button.",
         )
],
        [_("Plan this to-do for today or later"),
         _("Tap the calendar button at the bottom to decide when to complete this to-do.")
],
        [_("Reorder your to-dos"),
         _("To reorder your list, tap and hold a to-do, then drag it to where it should go.")
],
        [_("Create a project"),
         _(
           "Organize your to-dos better! Go to the left panel and click the '+' button in " \
                      "the 'On This Computer' section and add a project of your own.",
         )
],
        [_("You’re done!"),
         _(
           "That’s all you really need to know. Feel free to start adding your own projects " \
                      "and to-dos.\nYou can come back to this project later to learn the advanced " \
                      "features below.\nWe hope you’ll enjoy using Planify!",
         )
],
      ]
    end

    def tutorial_sections(_project)
      [
        [_("Tune your setup"),
         [[_("Show your calendar events"),
           _(
             "You can display your system's calendar events in Planify. Go to 'Preferences' " \
                          "🡒 General 🡒 Calendar Events to turn it on.",
           )
],
          [_("Enable synchronization with third-party services"),
           _(
             "Planify not only creates tasks locally, but can also synchronize with your " \
                          "Todoist account. Go to 'Preferences' 🡒 'Accounts'.",
           )
]
]
],
        [_("Boost your productivity"),
         [[_("Drag the plus button!"),
           _(
             "That blue button you see at the bottom of each screen is more powerful than " \
                          "it looks: it's made to move! Drag it up to create a task wherever you want.",
           )
],
          [_("Add labels to your tasks!"),
           _(
             "Labels help you organize and categorize your tasks. To add a label, click the " \
                          "label button at the bottom.",
           )
],
          [_("Set timely reminders!"),
           _(
             "Get notified about important tasks or events. Tap the clock button below to " \
                          "add a reminder.",
           )
]
]
],
      ]
    end

    def create_default_labels(store)
      [
        [_("💼️Work"), "taupe"],
        [_("🎒️School"), "berry_red"],
        [_("👉️Delegated"), "yellow"],
        [_("🏡️Home"), "lime_green"],
        [_("🏃‍♀️️Follow Up"), "grey"],
      ].each_with_index do |(name, color), index|
        store.insert_label(
          Label.new(name: name, color: color, item_order: index, source_id: "local"),
        )
      end
    end
  end
end
