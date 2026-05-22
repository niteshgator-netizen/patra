# frozen_string_literal: true

module Patra
  class OauthCallbackController < ActionController::Base
    layout false

    BM_APPS_URL = 'https://business.facebook.com/settings/apps'

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

      render html: oauth_success_html(result, account).html_safe
    rescue StandardError => e
      Rails.logger.error("[PatraBYOC] oauth callback failed: #{e.class}: #{e.message}")
      render html: oauth_error_html(e.message).html_safe
    end

    private

    def patra_oauth_redirect_uri
      "#{ENV.fetch('FRONTEND_URL', 'https://patrahq.com').to_s.chomp('/')}/patra/oauth/callback"
    end

    def oauth_page_styles
      <<~CSS
        body { font-family: system-ui, -apple-system, sans-serif; max-width: 540px; margin: 60px auto; padding: 0 24px; color: #1a1a1a; }
        .header { font-size: 24px; font-weight: 600; margin-bottom: 8px; }
        .header-success { color: #1d9e75; }
        .header-error { color: #c62828; }
        .sub { color: #666; font-size: 14px; margin-bottom: 24px; }
        ul { list-style: none; padding: 0; }
        .info-box { background: #f5f5f7; border: 1px solid #e5e5ea; border-radius: 8px; padding: 16px; margin: 24px 0; }
        .info-box h3 { margin: 0 0 8px; font-size: 15px; color: #1a1a1a; }
        .info-box p { margin: 0 0 12px; font-size: 13px; color: #555; line-height: 1.5; }
        .error-box { background: #fff5f5; border: 1px solid #ffcdd2; border-radius: 8px; padding: 16px; margin: 24px 0; }
        .error-box p { margin: 0; font-size: 14px; color: #555; line-height: 1.5; }
        .app-id-code { background: #fff; border: 1px solid #ddd; border-radius: 4px; padding: 4px 8px; font-family: monospace; font-size: 12px; }
        .btn { display: inline-block; background: #6464ff; color: white; padding: 10px 16px; border-radius: 6px; text-decoration: none; font-weight: 500; font-size: 14px; }
        .btn:hover { background: #5050e5; }
        .btn-secondary { background: #e5e5ea; color: #1a1a1a; }
        .btn-secondary:hover { background: #d1d1d6; }
      CSS
    end

    def oauth_success_html(result, account)
      pages_count = result[:pages].length
      page_label = pages_count == 1 ? 'page' : 'pages'
      pages_html = result[:pages].map do |p|
        "<li style=\"margin: 4px 0;\">✓ #{ERB::Util.html_escape(p[:name])}</li>"
      end.join
      app_id = ERB::Util.html_escape(account.meta_app_id)

      <<~HTML
        <html><head><style>#{oauth_page_styles}</style></head><body>
          <h2 class="header header-success">Connected #{pages_count} #{page_label}</h2>
          <p class="sub">You can close this window and return to Patra.</p>
          <ul>#{pages_html}</ul>

          <div class="info-box">
            <h3>Expecting more pages?</h3>
            <p>Pages owned by a Business Manager are hidden from Patra until you link your Meta app to that Business. Open Meta Business Settings and add app <span class="app-id-code">#{app_id}</span> to grant access.</p>
            <a href="#{BM_APPS_URL}" target="_blank" rel="noopener noreferrer" class="btn">Open Business Settings →</a>
          </div>

          <script>setTimeout(() => { try { window.close(); } catch(e){} }, 30000);</script>
        </body></html>
      HTML
    end

    def oauth_error_html(msg)
      <<~HTML
        <html><head><style>#{oauth_page_styles}</style></head><body>
          <h2 class="header header-error">Connection failed</h2>
          <p class="sub">We could not complete your Facebook connection.</p>
          <div class="error-box">
            <p>#{ERB::Util.html_escape(msg)}</p>
          </div>
          <p style="margin-top: 24px;">
            <a href="javascript:window.close()" class="btn btn-secondary">Close this window</a>
          </p>
        </body></html>
      HTML
    end
  end
end
