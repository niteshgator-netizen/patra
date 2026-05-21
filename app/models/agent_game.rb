# == Schema Information
#
# Table name: agent_games
#
#  id                      :bigint           not null, primary key
#  account_id              :bigint           not null
#  game_id                 :bigint           not null
#  status                  :string           default("inactive"), not null
#  credentials             :jsonb            default({}), not null
#  display_name            :string
#  notes                   :text
#  ip_whitelist_confirmed  :boolean          default(FALSE), not null
#  last_used_at            :datetime
#  last_failure_at         :datetime
#  failure_count           :integer          default(0), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
class AgentGame < ApplicationRecord
  STATUSES = %w[active inactive].freeze

  # Auto-disable threshold: if failure_count >= this AND last_failure_at within window,
  # status flips to 'inactive'. Bella will then skip this panel via pick_agent_game.
  AUTO_DISABLE_FAILURE_THRESHOLD = 5
  AUTO_DISABLE_WINDOW_HOURS = 1

  belongs_to :account
  belongs_to :game

  # Encrypt the credentials JSON at rest using Rails 7 encryption
  encrypts :credentials

  validates :status, inclusion: { in: STATUSES }
  validates :account_id, uniqueness: { scope: :game_id, message: "already has this game activated" }
  validate :credentials_must_be_hash
  validate :required_credentials_present, if: :active?

  scope :active, -> { where(status: 'active') }
  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :with_api_configured, -> { active.joins(:game).where(games: { has_api: true }) }

  def active?
    status == 'active'
  end

  def api_configured?
    return false unless game.has_api?
    return false unless ip_whitelist_confirmed?
    required_credential_keys = game.required_field_names
    required_credential_keys.all? { |key| credentials[key].present? }
  end

  def display_label
    display_name.presence || game&.name
  end

  def record_failure!
    new_count = failure_count + 1
    now = Time.current

    # If last failure was outside the window, reset counter (transient blip, not pattern)
    if last_failure_at && last_failure_at < AUTO_DISABLE_WINDOW_HOURS.hours.ago
      new_count = 1
    end

    attrs = { failure_count: new_count, last_failure_at: now }

    # Auto-disable if threshold crossed
    if new_count >= AUTO_DISABLE_FAILURE_THRESHOLD && status == 'active'
      attrs[:status] = 'inactive'
      Rails.logger.warn("[AgentGame] AUTO-DISABLED agent_game id=#{id} game=#{game&.slug} after #{new_count} failures in #{AUTO_DISABLE_WINDOW_HOURS}hr window")
    end

    update!(attrs)
  end

  def reset_failures!
    update!(failure_count: 0, last_failure_at: nil)
  end

  def mark_used!
    update!(last_used_at: Time.current)
  end

  # Returns credentials without exposing actual secret values
  # Useful for API responses where we don't want to leak secrets
  def safe_credentials
    return {} unless credentials.is_a?(Hash)
    credentials.transform_values.with_index do |value, idx|
      key = credentials.keys[idx]
      # Mask anything that looks like a secret
      if key.to_s.match?(/secret|password|key|token/i) && value.is_a?(String) && value.length > 4
        "#{value[0..3]}#{'*' * 16}"
      else
        value
      end
    end
  end

  private

  def credentials_must_be_hash
    return if credentials.is_a?(Hash)
    errors.add(:credentials, "must be a hash/object")
  end

  def required_credentials_present
    return unless game # game association may not be loaded yet
    missing = game.required_field_names.reject { |key| credentials[key].present? }
    return if missing.empty?
    errors.add(:credentials, "missing required fields: #{missing.join(', ')}")
  end
end
