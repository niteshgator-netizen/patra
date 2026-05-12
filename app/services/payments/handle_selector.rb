# frozen_string_literal: true

module Payments
  class HandleSelector
    def initialize(*args, **kwargs)
      @account = kwargs[:account] || args[0]
      @platform = (kwargs[:platform] || args[1])&.to_s&.downcase.presence
    end

    def pick_active
      return nil unless @account
      return nil if @platform.blank?

      @account.payment_handles.active_for(@platform).find(&:available?)
    end

    def pick_backup(failed_handle)
      return nil unless @account && failed_handle

      plat = @platform.presence || failed_handle.platform.to_s.downcase
      chain = @account.payment_handles.active_for(plat)
      idx = chain.to_a.index { |h| h.normalized_handle == failed_handle.normalized_handle }
      return chain.find(&:available?) if idx.nil?

      chain.to_a[(idx + 1)..]&.find(&:available?) || chain.find { |h| h.normalized_handle != failed_handle.normalized_handle && h.available? }
    end

    def pick(platform)
      self.class.new(@account, platform).pick_active
    end

    def usable_platforms
      return [] unless @account

      PaymentHandle::PLATFORMS.select { |p| self.class.new(@account, p).pick_active.present? }
    end
  end
end
