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

      candidates = @account.payment_handles
                           .active_for(@platform)
                           .to_a
                           .select(&:available?)

      return nil if candidates.empty?

      candidates.min_by { |h| [h.failure_count || 0, h.priority || 999] }
    end

    def pick_backup(failed_handle = nil)
      return nil unless @account

      plat = @platform.presence || failed_handle&.platform.to_s.downcase
      return nil if plat.blank?

      candidates = @account.payment_handles
                           .active_for(plat)
                           .to_a
                           .select(&:available?)

      return nil if candidates.empty?

      if failed_handle
        candidates = candidates.reject do |h|
          h.id == failed_handle.id ||
            h.normalized_handle == failed_handle.normalized_handle
        end
      end

      return nil if candidates.empty?

      candidates.min_by { |h| [h.failure_count || 0, h.priority || 999] }
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
