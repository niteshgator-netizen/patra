# frozen_string_literal: true

class Api::V1::Accounts::Patra::FacebookIdentitiesController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :find_identity, only: [:destroy, :reauthorize]

  def index
    identities = Current.account.facebook_identities.includes(:inboxes).order(:created_at)
    render json: identities.map { |fi| serialize_identity(fi) }
  end

  def destroy
    @identity.inboxes.update_all(facebook_identity_id: nil) if @identity.respond_to?(:inboxes)
    @identity.destroy!
    render json: { success: true }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def reauthorize
    render json: { error: 'Reauthorize via fb_connect flow' }, status: :not_implemented
  end

  private

  def find_identity
    @identity = Current.account.facebook_identities.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Identity not found' }, status: :not_found
  end

  def serialize_identity(fi)
    {
      id: fi.id,
      fb_user_id: fi.fb_user_id,
      fb_user_name: fi.fb_user_name,
      fb_user_avatar_url: fi.fb_user_avatar_url,
      status: fi.status,
      token_expires_at: fi.token_expires_at,
      inboxes: fi.inboxes.map { |i| { id: i.id, name: i.name } }
    }
  end
end
