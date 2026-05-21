class SecretPhrase < ApplicationRecord
  encrypts :phrase

  belongs_to :account
  belongs_to :user

  ACTIONS = %w[notify_only pause_ai_and_notify].freeze
  MIN_PHRASE_LENGTH = 3
  MAX_PHRASE_LENGTH = 50

  validates :action, inclusion: { in: ACTIONS }
  validates :phrase, presence: true, length: { in: MIN_PHRASE_LENGTH..MAX_PHRASE_LENGTH }
  validate :phrase_uniqueness_per_account

  scope :enabled, -> { where(active: true) }

  private

  def phrase_uniqueness_per_account
    return if phrase.blank? || account_id.blank?

    duplicate = SecretPhrase.where(account_id: account_id)
                          .where.not(id: id)
                          .pluck(:phrase)
                          .any? { |p| p.to_s.downcase == phrase.to_s.downcase }
    return unless duplicate

    errors.add(:phrase, 'already exists for this account (case-insensitive)')
  end
end
