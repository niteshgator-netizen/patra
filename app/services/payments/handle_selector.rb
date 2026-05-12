# frozen_string_literal: true

module Payments
  class HandleSelector
    def initialize(account)
      @account = account
    end

    def pick(platform)
      @account.payment_handles.active_for(platform).first
    end

    def any_usable?(platform)
      @account.payment_handles.active_for(platform).exists?
    end

    def usable_platforms
      @account.payment_handles
              .where(status: 'active')
              .where('cooldown_until IS NULL OR cooldown_until < ?', Time.current)
              .distinct
              .pluck(:platform)
    end
  end
end
