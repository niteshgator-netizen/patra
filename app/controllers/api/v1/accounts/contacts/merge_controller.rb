# frozen_string_literal: true

class Api::V1::Accounts::Contacts::MergeController < Api::V1::Accounts::Contacts::BaseController
  def create
    duplicate = Current.account.contacts.find(params[:duplicate_contact_id])
    primary = [@contact, duplicate].min_by(&:created_at)

    result = Contacts::MergeService.new(
      account: Current.account,
      primary_contact: primary,
      duplicate_contact: primary == @contact ? duplicate : @contact
    ).perform!

    render json: result
  end
end
