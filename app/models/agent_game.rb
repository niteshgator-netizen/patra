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
  STATUSES = %w[active inactive degraded].freeze

  # Auto-disable threshold: if failure_count >= this AND last_failure_at within window,
  # status flips to 'inactive'. Bella will then skip this panel via pick_agent_game.
  AUTO_DISABLE_FAILURE_THRESHOLD = 5
  AUTO_DISABLE_WINDOW_HOURS = 1

  # Feature 5 (auto-failover): a SEPARATE, simpler failover used by the new money
  # handlers (transfer v2 etc.) via record_api_failure!/record_api_success!.
  # 3 consecutive API failures -> 'degraded' + Telegram. Reset count on any success.
  # Intentionally does NOT touch the existing record_failure!/execute_in_audit path.
  API_DEGRADE_FAILURE_THRESHOLD = 3

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

  # Feature 5 auto-failover — increment on a game-API failure. At
  # API_DEGRADE_FAILURE_THRESHOLD consecutive failures, flip an ACTIVE panel to
  # 'degraded' (pick_agent_game then skips it) and fire a one-time Telegram alert.
  def record_api_failure!
    new_count = failure_count.to_i + 1
    attrs = { failure_count: new_count, last_failure_at: Time.current }

    just_degraded = false
    if new_count >= API_DEGRADE_FAILURE_THRESHOLD && status == 'active'
      attrs[:status] = 'degraded'
      just_degraded = true
    end

    update!(attrs)

    if just_degraded
      begin
        Games::TelegramNotifier.human_escalation(
          account: account,
          contact: nil,
          reason: [
            "PLAYER WANTS: keep playing #{game&.name || game&.slug} (panel is failing)",
            "ALREADY DONE: #{new_count} consecutive API failures — panel auto-set to degraded, Bella stopped routing to it",
            'STILL LEFT: panel stays degraded until a human reactivates it',
            'BELLA SUGGESTS: check the panel login/session, fix, then set status back to active',
            "NEEDS FROM HUMAN: review #{game&.name || game&.slug} and reactivate when healthy"
          ].join(' | ')
        )
      rescue StandardError => e
        Rails.logger.error("[AgentGame] degrade Telegram failed: #{e.class}: #{e.message}")
      end
    end
    new_count
  end

  # Feature 5 — reset the consecutive-failure counter on ANY success.
  # Status is intentionally left as-is (a degraded panel stays degraded for human
  # review; pick_agent_game already won't route to it, so no success can arrive
  # until a human reactivates it).
  def record_api_success!
    update!(failure_count: 0) if failure_count.to_i.positive?
  end

  def mark_used!
    update!(last_used_at: Time.current)
  end

  # Persist the result of a READ-ONLY test_connection so the dashboard badge can
  # reflect the REAL last connection state (not the static api_configured? flag).
  def record_connection_test!(ok:, message: nil)
    update!(
      last_connection_ok: ok,
      last_connection_checked_at: Time.current,
      last_connection_message: message.to_s[0, 255].presence
    )
  end

  # :connected / :failed / :untested  (nil last_connection_ok = never tested)
  def connection_status
    return :untested if last_connection_ok.nil?

    last_connection_ok ? :connected : :failed
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
