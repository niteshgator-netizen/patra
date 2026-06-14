# This file is used to render conversation data search API response.

json.id conversation.display_id
json.uuid conversation.uuid
json.created_at conversation.created_at.to_i
json.contact do
  json.id conversation.contact.id
  json.name Patra::ContactPrivacy.display_name(conversation.contact, Current.account_user)
end
json.inbox do
  json.id conversation.inbox.id
  json.name conversation.inbox.name
  json.channel_type conversation.inbox.channel_type
end
json.messages do
  json.array! conversation.messages do |message|
    json.content message.content
    json.id message.id
    if message.sender
      json.sender_name(
        message.sender.is_a?(Contact) ? Patra::ContactPrivacy.display_name(message.sender, Current.account_user) : message.sender.name
      )
    end
    json.message_type message.message_type_before_type_cast
    json.created_at message.created_at.to_i
  end
end
json.account_id conversation.account_id
