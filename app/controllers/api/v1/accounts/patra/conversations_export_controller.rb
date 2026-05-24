# frozen_string_literal: true

class Api::V1::Accounts::Patra::ConversationsExportController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    conversations = Current.account.conversations.includes(:contact, :inbox, :labels).limit(5000)

    csv = CSV.generate do |row|
      row << %w[id contact_name channel status created_at resolved_at messages_count labels]
      conversations.find_each do |conv|
        row << [
          conv.display_id,
          conv.contact&.name,
          conv.inbox&.name,
          conv.status,
          conv.created_at&.iso8601,
          (conv.updated_at.iso8601 if conv.resolved?),
          conv.messages.count,
          conv.labels.pluck(:title).join(';')
        ]
      end
    end

    send_data csv, filename: "conversations-#{Date.current}.csv", type: 'text/csv'
  end

  private

  def check_authorization
    authorize :report, :view?
  end
end
