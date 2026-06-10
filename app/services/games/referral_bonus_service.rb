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

      begin
        # TAB A: wire the Settings -> Referrals page (these values persisted to
        # ReplyPreference but were never read - the page was decorative and the
        # amounts hardcoded). referral_enabled defaults FALSE, so auto-pay stays
        # OFF until the operator flips it. respond_to? guards keep this safe if
        # the columns migration has not deployed yet (winback pattern).
        pref = ReplyPreference.for_account(@account.id)
        return unless pref.respond_to?(:referral_enabled) && pref.referral_enabled

        # Only the freeplay payout path exists - any other configured bonus
        # type is left at 'verified' for manual handling (cashier already
        # gets the Telegram escalation from the orchestrator).
        bonus_type = pref.respond_to?(:referral_bonus_type) ? (pref.referral_bonus_type.presence || 'freeplay') : 'freeplay'
        return unless bonus_type == 'freeplay'

        require_deposit = pref.respond_to?(:referral_require_deposit) ? pref.referral_require_deposit != false : true
        if require_deposit
          has_deposit = GameAction.where(contact_id: referred.id)
            .where(action_type: %w[load recharge])
            .exists?
          return unless has_deposit
        end

        referrer_bonus = (pref.respond_to?(:referral_bonus_referrer) ? pref.referral_bonus_referrer : nil).to_f
        referrer_bonus = 5.0 unless referrer_bonus.positive?
        referred_bonus = (pref.respond_to?(:referral_bonus_new_player) ? pref.referral_bonus_new_player : nil).to_f
        referred_bonus = 5.0 unless referred_bonus.positive?

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
        attrs = contact.custom_attributes || {}
        # TAB A fix: (1) vault stores 'milkyway'-style values while agent_games
        # use 'milky_way' slugs - map them; (2) usernames are stored under
        # "game_username_<slug>" (orchestrator store_game_username), the old
        # "<slug>_username" key never matched so referral bonuses NEVER paid;
        # (3) only active agent_games - never load freeplay on a dead panel.
        preferred_raw = attrs['preferred_platform'].to_s.downcase.strip
        preferred_slug = Games::ConversationOrchestrator::PREFERRED_PLATFORM_TO_SLUG[preferred_raw] ||
                         preferred_raw.presence

        actives = AgentGame.where(account_id: @account.id, status: 'active').includes(:game).to_a
        ordered = actives.sort_by { |ag| ag.game.slug == preferred_slug ? 0 : 1 }
        agent_game = ordered.find { |ag| attrs["game_username_#{ag.game.slug}"].present? }
        return unless agent_game

        game_slug = agent_game.game.slug
        username = attrs["game_username_#{game_slug}"]
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
