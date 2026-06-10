class Webhooks::TelegramController < ActionController::API
  before_action :validate_telegram_secret_token

  def process_payload
    Webhooks::TelegramEventsJob.perform_later(params.to_unsafe_hash)
    head :ok
  end

  private

  # Telegram echoes the secret_token registered via setWebhook in this header.
  # Enforcement is opt-in (TELEGRAM_WEBHOOK_VALIDATE_SECRET=true) because
  # webhooks registered before this change carry no secret; re-register them
  # (re-save the Telegram channel) before enabling, or all events get 401.
  def validate_telegram_secret_token
    expected = Webhooks::TelegramSecret.for(params[:bot_token])
    provided = request.headers['X-Telegram-Bot-Api-Secret-Token'].to_s
    return if ActiveSupport::SecurityUtils.secure_compare(provided, expected)

    if ENV['TELEGRAM_WEBHOOK_VALIDATE_SECRET'] == 'true'
      head :unauthorized
    else
      Rails.logger.warn('[TelegramWebhook] missing/mismatched secret token (enforcement off — set TELEGRAM_WEBHOOK_VALIDATE_SECRET=true after re-registering webhooks)')
    end
  end
end
