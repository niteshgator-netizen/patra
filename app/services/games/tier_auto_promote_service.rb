# frozen_string_literal: true

module Games
  class TierAutoPromoteService
    def initialize(contact:)
      @contact = contact
      @account = contact.account
    end

    def call
      return unless @account
      return if @contact.player_tier&.name == 'blocked'

      # Find the VIP tier with auto-promote rules
      vip_tier = @account.player_tiers.find_by(name: 'vip')
      return unless vip_tier
      return unless vip_tier.auto_promote_deposit_threshold&.positive?

      # Already VIP or higher? Skip
      current_tier = @contact.player_tier
      return if current_tier&.name == 'vip'
      return if current_tier&.name == 'selected' # selected is manual-only, don't downgrade

      # Calculate total deposits
      # TAB A fix: only SUCCESSFUL, non-freeplay loads are deposits. Failed and
      # pending loads and freeplay credits counted toward VIP promotion before
      # (10 failed $100 loads = VIP). Same convention as the orchestrator's
      # cashout-multiplier math.
      begin
        deposits_scope = GameAction.where(contact_id: @contact.id)
          .where(action_type: %w[load recharge], status: 'success')
          .where("COALESCE(metadata->>'freeplay', 'false') != 'true'")

        total_deposits = deposits_scope.sum(:amount).to_f
        deposit_count = deposits_scope.count

        # Check threshold
        meets_amount = total_deposits >= vip_tier.auto_promote_deposit_threshold
        meets_count = vip_tier.auto_promote_after_deposits.nil? ||
                      deposit_count >= vip_tier.auto_promote_after_deposits

        if meets_amount && meets_count
          @contact.update!(player_tier: vip_tier)
          Rails.logger.info("[TierAutoPromote] Contact #{@contact.id} (#{@contact.name}) promoted to VIP. Deposits: $#{total_deposits}, count: #{deposit_count}")
          true
        else
          false
        end
      rescue StandardError => e
        Rails.logger.error("[TierAutoPromote] Failed for contact #{@contact.id}: #{e.message}")
        false
      end
    end

    # Class method for easy calling
    def self.check(contact:)
      new(contact: contact).call
    end

    # Check new players — assign new_player tier if no tier set
    def self.assign_new_player_tier(contact:)
      return if contact.player_tier_id.present?

      new_player_tier = contact.account&.player_tiers&.find_by(name: 'new_player')
      return unless new_player_tier

      begin
        has_any_action = GameAction.where(contact_id: contact.id).exists?
        unless has_any_action
          contact.update!(player_tier: new_player_tier)
          Rails.logger.info("[TierAutoPromote] Contact #{contact.id} assigned new_player tier")
        end
      rescue StandardError => e
        Rails.logger.error("[TierAutoPromote] New player assign failed: #{e.message}")
      end
    end
  end
end
