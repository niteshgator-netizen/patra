# frozen_string_literal: true

# patra-final P3: agent → owner feedback (bug reports, player issues,
# suggestions). Never player-facing. Admins get an in-app notification
# per new entry.
class PatraAgentFeedback < ApplicationRecord
  belongs_to :account
  belongs_to :user
  belongs_to :conversation, optional: true
  belongs_to :contact, optional: true

  validates :body, presence: true, length: { maximum: 10_000 }

  enum category: { bug: 0, player_issue: 1, suggestion: 2, other: 3 }, _prefix: :category
  enum status: { new: 0, seen: 1 }, _prefix: :status

  after_create_commit :notify_admins

  # Consumed by Notification#push_event_data via primary_actor.
  def push_event_data
    {
      id: id,
      category: category,
      status: status,
      body: body.to_s.truncate(140),
      conversation_display_id: conversation&.display_id,
      submitted_by: user&.name,
      created_at: created_at.to_i
    }
  end

  private

  # Best-effort: a notification failure must never roll back or crash
  # feedback creation.
  def notify_admins
    account.administrators.each do |admin|
      next if admin.id == user_id

      Notification.create(
        account: account,
        user: admin,
        notification_type: :patra_agent_feedback,
        primary_actor: self,
        meta: { category: category, submitted_by: user&.name }
      )
    end
  rescue StandardError => e
    Rails.logger.error "PatraAgentFeedback#notify_admins failed: #{e.message}"
  end
end
