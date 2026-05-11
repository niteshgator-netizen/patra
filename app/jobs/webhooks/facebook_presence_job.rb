# Updates Redis last-active for a Facebook user from read-receipt webhooks (no message body).
class Webhooks::FacebookPresenceJob < ApplicationJob
  queue_as :default

  def perform(messaging)
    messaging = messaging.with_indifferent_access if messaging.respond_to?(:with_indifferent_access)
    sender_id = messaging.dig('sender', 'id').to_s
    page_id = (
      messaging['_patra_fb_page_id'] ||
      messaging[:_patra_fb_page_id] ||
      messaging.dig('recipient', 'id')
    ).to_s
    return if sender_id.blank? || page_id.blank?

    contact_id = Facebook::ChatwootBridgeService.find_contact_id_by_psid(sender_id, page_id: page_id)
    return if contact_id.blank?

    at = messenger_timestamp(messaging) || Time.current
    Facebook::ContactLastActive.record!(contact_id, at: at)
  end

  private

  def messenger_timestamp(messaging)
    ts = messaging['timestamp'] || messaging[:timestamp]
    return nil if ts.blank?

    Time.zone.at(ts.to_f / 1000.0)
  end
end
