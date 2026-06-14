# frozen_string_literal: true

# Patra (it7) — owner-only management of a manager's "main feature" grants.
#
#   GET  .../main_feature_grants/:id  -> current granted_main_features for that account_user
#   PUT  .../main_feature_grants/:id  -> replace granted_main_features (whitelisted)
#
# :id is the AccountUser id within the current account. Only the workspace OWNER may read or write
# grants; everyone else (including non-owner admins/managers) is denied.
class Api::V1::Accounts::MainFeatureGrantsController < Api::V1::Accounts::BaseController
  include Patra::MainFeatureGuard

  before_action :authorize_owner!
  before_action :fetch_account_user

  def show
    render json: grant_payload
  end

  def update
    @account_user.update!(granted_main_features: sanitize_features(params[:granted_main_features]))
    render json: grant_payload
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def authorize_owner!
    return if Current.user&.owner_of?(Current.account)

    render json: { error: 'Only the workspace owner can manage feature grants.' }, status: :forbidden
  rescue StandardError
    render json: { error: 'Only the workspace owner can manage feature grants.' }, status: :forbidden
  end

  def fetch_account_user
    @account_user = Current.account.account_users.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Account user not found.' }, status: :not_found
  end

  # Keep only recognised, whitelisted feature keys; dedupe; coerce to strings.
  def sanitize_features(raw)
    Array(raw).map(&:to_s).uniq & Patra::MainFeatureGuard::MAIN_FEATURES
  end

  def grant_payload
    {
      account_user_id: @account_user.id,
      user_id: @account_user.user_id,
      granted_main_features: Array(@account_user.granted_main_features),
      available_main_features: Patra::MainFeatureGuard::MAIN_FEATURES
    }
  end
end
