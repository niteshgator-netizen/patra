# MEGA2 P4 - inbound webhook for the Patra ops bot (the TELEGRAM_BOT_TOKEN
# notifier bot), SEPARATE from webhooks/telegram (Channel::Telegram inboxes).
# Register with: setWebhook url=https://<host>/webhooks/patra_telegram_ops
# secret_token=<PATRA_TELEGRAM_OPS_WEBHOOK_SECRET>.
# Feature is DARK unless PATRA_TELEGRAM_COMMANDS='true' (updates ack'd + dropped).
class Webhooks::PatraTelegramOpsController < ActionController::API
  before_action :validate_ops_secret

  def process_payload
    if TelegramOps::CommandHandler.feature_enabled?
      TelegramOps::CommandJob.perform_later(params.to_unsafe_hash)
    end
    head :ok
  end

  private

  # Telegram echoes the secret_token registered via setWebhook in this header.
  # Enforcement is ON whenever PATRA_TELEGRAM_OPS_WEBHOOK_SECRET is set; with
  # no secret configured the check is DARK (warn-log only, accepts the update).
  def validate_ops_secret
    expected = ENV['PATRA_TELEGRAM_OPS_WEBHOOK_SECRET'].to_s
    if expected.blank?
      Rails.logger.warn('[TelegramOps] webhook secret not configured - accepting unverified update (set PATRA_TELEGRAM_OPS_WEBHOOK_SECRET and re-register the webhook to enforce)')
      return
    end

    provided = request.headers['X-Telegram-Bot-Api-Secret-Token'].to_s
    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(provided, expected)
  end
end
