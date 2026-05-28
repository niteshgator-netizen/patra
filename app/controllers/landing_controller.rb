class LandingController < ActionController::Base
  def show
    render file: Rails.root.join('public', 'patra-landing.html'), layout: false
  end
end
