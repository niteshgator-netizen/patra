# frozen_string_literal: true

class AddRecurrenceToScheduledMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :scheduled_messages, :recurrence, :string
    add_column :scheduled_messages, :recurrence_end_at, :datetime
  end
end
