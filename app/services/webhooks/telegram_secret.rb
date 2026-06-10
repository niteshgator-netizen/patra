# Derives the per-bot webhook secret Telegram echoes back in the
# X-Telegram-Bot-Api-Secret-Token header (set via setWebhook secret_token).
# HMAC over the bot token keyed by secret_key_base — deterministic, so no
# DB column is needed and web + worker always agree.
# Telegram allows 1-256 chars of [A-Za-z0-9_-]; a hex digest fits.
class Webhooks::TelegramSecret
  def self.for(bot_token)
    OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base.to_s, bot_token.to_s)
  end
end
