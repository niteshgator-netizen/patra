# Async worker that forwards an outgoing Chatwoot message to Facebook via the
# Send API. Failures inside the service are swallowed (return false) so a bad
# Graph response doesn't trigger Sidekiq retry storms — the service logs the
# error and we move on.
class Webhooks::FbReplyJob < ApplicationJob
  queue_as :default

  def perform(conversation_id, message_content, account_id = nil)
    Facebook::SendApiService.new(conversation_id, message_content, account_id: account_id).call
  end
end
