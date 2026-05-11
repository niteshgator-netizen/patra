# frozen_string_literal: true

module Players
  # Maps deposit_count + largest single deposit to a loyalty_tier label for
  # contact custom_attributes and AI tone hints.
  class LoyaltyCalculator
    TIERS = %w[new casual regular loyal vip].freeze

    class << self
      # @param deposit_count [Integer] number of recorded deposits
      # @param max_single_deposit [Numeric] largest single deposit in dollars (0 if unknown)
      # @return [String] one of TIERS
      def tier(deposit_count:, max_single_deposit:)
        count = deposit_count.to_i
        max_single = max_single_deposit.to_f

        return 'vip' if max_single > 100.0
        return 'vip' if count >= 30

        case count
        when 0..1 then 'new'
        when 2..5 then 'casual'
        when 6..15 then 'regular'
        when 16..29 then 'loyal'
        else 'new'
        end
      end

      def valid_tier?(value)
        TIERS.include?(value.to_s)
      end
    end
  end
end
