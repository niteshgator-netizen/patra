# frozen_string_literal: true

class Api::V1::Accounts::Contacts::TimelineController < Api::V1::Accounts::BaseController
  def show
    contact = Current.account.contacts.find(params[:contact_id])
    events = Contacts::TimelineBuilder.new(contact).events
    render json: { events: events }
  end
end
