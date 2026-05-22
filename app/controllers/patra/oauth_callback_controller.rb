# frozen_string_literal: true

module Patra
  class OauthCallbackController < ActionController::Base
    layout false

    def handle
      if params[:error].present?
        render html: oauth_error_html(params[:error_description] || params[:error]).html_safe
        return
      end

      state_data = Patra::OauthState.verify(params[:state])
      raise StandardError, 'Invalid or expired state' unless state_data

      account = Account.find(state_data['account_id'])
      raise StandardError, 'Account has no BYOC Meta app configured' unless account.byoc_meta_app?

      result = Patra::ByocOauthService.new(
        account: account,
        code: params[:code],
        redirect_uri: patra_oauth_redirect_uri
      ).complete!

      render html: oauth_success_html(result).html_safe
    rescue StandardError => e
      Rails.logger.error("[PatraBYOC] oauth callback failed: #{e.class}: #{e.message}")
      render html: oauth_error_html(e.message).html_safe
    end

    private

    def patra_oauth_redirect_uri
      "#{ENV.fetch('FRONTEND_URL', 'https://patrahq.com').to_s.chomp('/')}/patra/oauth/callback"
    end

    def oauth_success_html(result)
      pages_html = result[:pages].map { |p| "<li>#{ERB::Util.html_escape(p[:name])}</li>" }.join
      <<~HTML
        <html><body style="font-family: system-ui; max-width: 480px; margin: 80px auto; text-align: center;">
          <h2 style="color: #1d9e75;">Connected #{result[:pages].length} pages</h2>
          <ul style="text-align: left;">#{pages_html}</ul>
          <p style="color: #888;">You can close this window and return to Patra.</p>
          <script>setTimeout(() => window.close(), 3000);</script>
        </body></html>
      HTML
    end

    def oauth_error_html(msg)
      <<~HTML
        <html><body style="font-family: system-ui; max-width: 480px; margin: 80px auto; text-align: center;">
          <h2 style="color: #c62828;">Connection failed</h2>
          <p>#{ERB::Util.html_escape(msg)}</p>
          <p><a href="javascript:window.close()">Close</a></p>
        </body></html>
      HTML
    end
  end
end
