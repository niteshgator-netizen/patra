json.email contact.email
json.id contact.id
json.name Patra::ContactPrivacy.display_name(contact, Current.account_user)
json.phone_number contact.phone_number
json.identifier contact.identifier
json.additional_attributes contact.additional_attributes
json.last_activity_at contact.last_activity_at&.to_i
