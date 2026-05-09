# Custom Facebook Messenger webhook endpoint at /webhooks/messenger.
#
# Chatwoot's default Facebook integration is mounted by the facebook-messenger
# gem at /bot. This controller adds an alternative URL that points at the same
# downstream processing (Webhooks::FacebookEventsJob), so a Meta app can be
# configured against /webhooks/messenger without changing gem internals.
#
#   GET  /webhooks/messenger — verification handshake against FB_VERIFY_TOKEN
#   POST /webhooks/messenger — events forwarded to FacebookEventsJob
#
# Follows the same shape as Webhooks::InstagramController:
#   - extends ActionController::API
#   - includes MetaTokenVerifyConcern for signature verification
#   - defines valid_token? + meta_app_secrets per Meta's standard contract
class Webhooks::MessengerController < ActionController::API
  include MetaTokenVerifyConcern

  before_action :verify_meta_signature!, only: :events

  # GET /webhooks/messenger
  def verify
    if valid_token?(params['hub.verify_token'])
      Rails.logger.info('Messenger webhook verified')
      render plain: params['hub.challenge']
    else
      Rails.logger.warn('Messenger webhook verify failed — invalid token')
      render status: :unauthorized, json: { error: 'Invalid verify token' }
    end
  end

  # POST /webhooks/messenger
  def events
    Rails.logger.info('Messenger webhook received events')

    if params['object'] != 'page'
      Rails.logger.warn("Messenger webhook ignored unexpected object=#{params['object']}")
      head :unprocessable_entity
      return
    end

    enqueue_events
    render json: :ok
  end

  private

  # Reuse the facebook-messenger gem's parser to produce the exact event JSON
  # shape Webhooks::FacebookEventsJob → Integrations::Facebook::MessageParser
  # already understand. Identical pipeline as the gem-mounted /bot endpoint.
  def enqueue_events
    Facebook::Messenger::Incoming.parse(request.raw_post).each do |event|
      Webhooks::FacebookEventsJob.perform_later(event.to_json)
    end
  rescue StandardError => e
    Rails.logger.error("Messenger webhook parse error: #{e.message}")
  end

  def valid_token?(token)
    token == GlobalConfigService.load('FB_VERIFY_TOKEN', '')
  end

  # Used by MetaTokenVerifyConcern#verify_meta_signature! to validate the
  # X-Hub-Signature-256 HMAC header. Try the per-page channel secrets first,
  # fall back to the global FB_APP_SECRET.
  def meta_app_secrets
    secrets = page_channel_app_secrets
    secrets << GlobalConfigService.load('FB_APP_SECRET', nil)
    secrets.compact_blank.uniq
  end

  def page_channel_app_secrets
    Array(params.to_unsafe_hash[:entry]).flat_map do |entry|
      channel = Channel::FacebookPage.find_by(page_id: entry[:id])
      channel_meta_app_secrets(channel)
    end
  end
end
