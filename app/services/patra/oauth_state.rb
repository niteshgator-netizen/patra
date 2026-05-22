# frozen_string_literal: true

module Patra
  class OauthState
    TTL_SECONDS = 600
    PURPOSE = 'patra_byoc_oauth'

    def self.generate(account_id:)
      payload = {
        account_id: account_id,
        nonce: SecureRandom.hex(8)
      }.to_json
      Rails.application.message_verifier(PURPOSE).generate(payload, expires_in: TTL_SECONDS)
    end

    def self.verify(token)
      return nil if token.blank?

      payload = Rails.application.message_verifier(PURPOSE).verified(token)
      return nil unless payload

      JSON.parse(payload)
    rescue StandardError
      nil
    end
  end
end
