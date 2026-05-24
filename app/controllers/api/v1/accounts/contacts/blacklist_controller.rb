# frozen_string_literal: true

class Api::V1::Accounts::Contacts::BlacklistController < Api::V1::Accounts::Contacts::BaseController
  def update
    attrs = (@contact.custom_attributes || {}).stringify_keys
    attrs['blacklisted'] = ActiveModel::Type::Boolean.new.cast(params[:blacklisted])
    attrs['blacklist_reason'] = params[:blacklist_reason] if params.key?(:blacklist_reason)
    @contact.update!(custom_attributes: attrs)

    Audit::Logger.log!(
      account: Current.account,
      user: current_user,
      action: attrs['blacklisted'] ? 'contact_blacklisted' : 'contact_unblacklisted',
      target: @contact,
      metadata: { reason: attrs['blacklist_reason'] }
    )

    render json: { blacklisted: attrs['blacklisted'], blacklist_reason: attrs['blacklist_reason'] }
  end
end
