# Public, unauthenticated static pages for Privacy Policy and Terms of Service.
# Required for Meta App Review (Facebook/Instagram/WhatsApp integrations) and
# any app store / OAuth provider that needs a public privacy policy URL.
#
# Extends ActionController::Base directly (not ApplicationController) so we
# don't inherit any current-user lookup, exception wrappers, or other request
# concerns that aren't needed for static content.
class LegalController < ActionController::Base
  layout 'legal'

  # GET /privacy
  def privacy
    @last_updated = 'May 9, 2026'
  end

  # GET /terms
  def terms
    @last_updated = 'May 9, 2026'
  end
end
