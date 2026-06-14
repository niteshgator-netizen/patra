json.additional_attributes resource.additional_attributes
json.availability_status resource.availability_status
json.email resource.email
json.id resource.id
json.name Patra::ContactPrivacy.display_name(resource, Current.account_user)
json.phone_number resource.phone_number
json.blocked resource.blocked
json.identifier resource.identifier
json.thumbnail resource.avatar_url
json.custom_attributes resource.custom_attributes
json.player_tier_id resource.player_tier_id
if resource.player_tier.present?
  json.player_tier do
    json.id resource.player_tier.id
    json.name resource.player_tier.name
    json.color resource.player_tier.color
    json.badge_text resource.player_tier.badge_text
  end
end
json.profile_stats resource.profile_stats
json.payment_status begin
  Payments::ContactPaymentStatus.new(contact: resource).display_pill
rescue StandardError
  nil
end
json.last_activity_at resource.last_activity_at.to_i if resource[:last_activity_at].present?
json.created_at resource.created_at.to_i if resource[:created_at].present?
# we only want to output contact inbox when its /contacts endpoints
if defined?(with_contact_inboxes) && with_contact_inboxes.present?
  json.contact_inboxes do
    json.array! resource.contact_inboxes do |contact_inbox|
      json.partial! 'api/v1/models/contact_inbox', formats: [:json], resource: contact_inbox
    end
  end
end
