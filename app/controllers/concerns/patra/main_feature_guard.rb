# frozen_string_literal: true

# Patra (it7) — authorize "main feature" mutations.
#
# Main features are the powerful, owner-level workspace controls: Facebook connections, payment
# handles, backup pages, custom roles, billing and game credentials. Authorization rule:
#   * the workspace OWNER (account creator) ALWAYS passes;
#   * a non-owner administrator (a "manager") passes ONLY for features the owner has explicitly
#     granted that membership via AccountUser#granted_main_features;
#   * everyone else (support, plain agents) is denied.
#
# Resolution is wrapped so any unexpected error denies (fail-closed, the safe direction).
module Patra
  module MainFeatureGuard
    extend ActiveSupport::Concern

    # Whitelist of grantable main features. Single source of truth shared with
    # MainFeatureGrantsController (which validates incoming grant keys against this list).
    MAIN_FEATURES = %w[
      facebook_connections
      payment_handles
      backup_pages
      roles
      billing
      game_credentials
    ].freeze

    private

    def check_main_feature_authorization!(feature)
      key = feature.to_s
      return if Current.user&.owner_of?(Current.account)
      return if Current.account_user&.granted?(key)

      render_main_feature_forbidden
    rescue StandardError
      render_main_feature_forbidden
    end

    def render_main_feature_forbidden
      render json: { error: 'You are not authorized to manage this feature.' }, status: :forbidden
    end
  end
end
