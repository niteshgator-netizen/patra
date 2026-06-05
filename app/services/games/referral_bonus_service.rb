# frozen_string_literal: true

module Games
  class ReferralBonusService
    def initialize(account:)
      @account = account
    end

    # Create a referral record when someone mentions referring
    def create_referral(referrer_contact:, referred_contact: nil)
      begin
        referral = @account.referrals.create!(
          referrer_contact: referrer_contact,
          referred_contact: referred_contact,
          status: 'pending',
          bonus_type: 'freeplay'
        )
        Rails.logger.info("[ReferralBonus] Referral created: #{referrer_contact.name} → #{referred_contact&.name || 'pending'}")
        referral
      rescue StandardError => e
        Rails.logger.error("[ReferralBonus] Create failed: #{e.message}")
        nil
      end
    end

    # Link a referred contact to an existing pending referral
    def link_referred(referral:, referred_contact:)
      begin
        referral.update!(referred_contact: referred_contact, status: 'verified')
        Rails.logger.info("[ReferralBonus] Linked #{referred_contact.name} to referral #{referral.id}")

        # Check if we should auto-pay
        check_and_pay(referral)
      rescue StandardError => e
        Rails.logger.error("[ReferralBonus] Link failed: #{e.message}")
      end
    end

    # Check if referral bonus should be paid
    def check_and_pay(referral)
      return unless referral.status.in?(%w[verified])

      referred = referral.referred_contact
      return unless referred

      # Check if referred player has made a deposit (configurable requirement)
      begin
        has_deposit = GameAction.where(contact_id: referred.id)
          .where(action_type: %w[load recharge])
          .exists?

        # For now, require at least one deposit before paying referral bonus
        # TODO: Make this configurable via a referral_settings table
        return unless has_deposit

        # Default bonus amount — $5 freeplay each
        referrer_bonus = 5.0
        referred_bonus = 5.0

        # Pay referrer bonus
        pay_freeplay_bonus(
          contact: referral.referrer_contact,
          amount: referrer_bonus,
          reason: "referral bonus — referred #{referred.name}"
        )

        # Pay referred bonus
        pay_freeplay_bonus(
          contact: referred,
          amount: referred_bonus,
          reason: "welcome bonus — referred by #{referral.referrer_contact.name}"
        )

        referral.mark_paid!(amount: referrer_bonus + referred_bonus, type: 'freeplay')
        Rails.logger.info("[ReferralBonus] Paid referral #{referral.id}: $#{referrer_bonus} to referrer, $#{referred_bonus} to referred")
      rescue StandardError => e
        Rails.logger.error("[ReferralBonus] Payment failed for referral #{referral.id}: #{e.message}")
      end
    end

    private

    def pay_freeplay_bonus(contact:, amount:, reason:)
      # Find the contact's preferred game or first available
      begin
        preferred_slug = contact.custom_attributes&.dig('preferred_platform')
        agent_game = if preferred_slug
          AgentGame.joins(:game).find_by(account_id: @account.id, games: { slug: preferred_slug })
        end
        agent_game ||= AgentGame.where(account_id: @account.id).first

        return unless agent_game

        game_slug = agent_game.game.slug
        username = contact.custom_attributes&.dig("#{game_slug}_username")
        return unless username

        executor = Games::ActionExecutor.new(agent_game: agent_game, contact: contact)
        result = executor.load_player(
          game_username: username,
          amount: amount.to_i,
          metadata: { freeplay: true, reason: reason, source: 'referral_bonus' }
        )

        if result[:ok]
          Rails.logger.info("[ReferralBonus] Freeplay $#{amount} loaded on #{game_slug} for #{contact.name}")
        else
          Rails.logger.error("[ReferralBonus] Freeplay load failed on #{game_slug}: #{result[:error]}")
        end
      rescue StandardError => e
        Rails.logger.error("[ReferralBonus] pay_freeplay_bonus failed: #{e.message}")
      end
    end

    # Class method for easy calling
    def self.create(account:, referrer_contact:, referred_contact: nil)
      new(account: account).create_referral(referrer_contact: referrer_contact, referred_contact: referred_contact)
    end
  end
end
