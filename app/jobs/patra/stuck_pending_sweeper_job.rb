# frozen_string_literal: true

# MEGA2 P10 - alert-only sweeper for stuck money state. Finds pending
# ApprovalRequests and pending GameActions older than PATRA_STUCK_MINUTES
# (default 30) and sends ONE grouped 5-part Telegram alert, at most once per
# hour (Redis stamp). NEVER acts on the stuck records - alerts only, so it is
# dark-safe by design.
class Patra::StuckPendingSweeperJob < ApplicationJob
  queue_as :low

  ALERT_STAMP_KEY = 'patra:stuck_sweeper:alerted_at'
  ALERT_INTERVAL_SECONDS = 60 * 60
  MAX_LINES_PER_KIND = 15

  def perform
    minutes = ENV.fetch('PATRA_STUCK_MINUTES', '30').to_i
    minutes = 30 unless minutes.positive?
    cutoff = minutes.minutes.ago

    stuck_approvals = ApprovalRequest.where(status: 'pending').where('created_at < ?', cutoff).order(:id).to_a
    stuck_actions = GameAction.where(status: 'pending').where('created_at < ?', cutoff).order(:id).to_a
    return if stuck_approvals.empty? && stuck_actions.empty?
    return if alerted_recently?

    lines = []
    stuck_approvals.first(MAX_LINES_PER_KIND).each do |a|
      lines << "approval ##{a.id} #{a.action_type} $#{a.amount} account=#{a.account_id} pending #{age_minutes(a)}m"
    end
    lines << "(+#{stuck_approvals.size - MAX_LINES_PER_KIND} more approvals)" if stuck_approvals.size > MAX_LINES_PER_KIND
    stuck_actions.first(MAX_LINES_PER_KIND).each do |g|
      lines << "game_action ##{g.id} #{g.action_type} $#{g.amount} order=#{g.order_id} pending #{age_minutes(g)}m"
    end
    lines << "(+#{stuck_actions.size - MAX_LINES_PER_KIND} more actions)" if stuck_actions.size > MAX_LINES_PER_KIND

    text = 'PLAYER WANTS: their stuck loads/cashouts finished | ' \
           "ALREADY DONE: sweep found #{stuck_approvals.size} pending approval(s) + #{stuck_actions.size} pending game action(s) older than #{minutes}m - NOTHING auto-acted | " \
           "STILL LEFT: #{lines.join('; ')} | " \
           'BELLA SUGGESTS: approve/deny the approvals and verify the pending actions on the panel before any redo | ' \
           "NEEDS FROM HUMAN: clear each stuck record (reply 'approve <id>' / 'deny <id>' works for approvals when commands are on)"

    Games::TelegramNotifier.send_to_cashout_group(text)
    stamp_alerted!
  rescue StandardError => e
    Rails.logger.error("[StuckPendingSweeper] #{e.class}: #{e.message}")
  end

  private

  def age_minutes(record)
    ((Time.current - record.created_at) / 60).to_i
  end

  def alerted_recently?
    Redis::Alfred.get(ALERT_STAMP_KEY).present?
  rescue StandardError
    false
  end

  def stamp_alerted!
    Redis::Alfred.set(ALERT_STAMP_KEY, Time.current.iso8601, ex: ALERT_INTERVAL_SECONDS)
  rescue StandardError
    nil
  end
end
