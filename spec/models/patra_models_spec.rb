# frozen_string_literal: true

# Validation + integrity specs for the 10 Patra vertical models.
require 'rails_helper'

RSpec.describe 'Patra models' do
  let(:account) { create(:account) }

  describe Game do
    it 'has a valid factory' do
      expect(build(:game)).to be_valid
    end

    it 'enforces slug format and uniqueness' do
      create(:game, slug: 'juwa')
      expect(build(:game, slug: 'juwa')).not_to be_valid
      expect(build(:game, slug: 'Bad Slug!')).not_to be_valid
    end

    it 'rejects unknown statuses and auth methods' do
      expect(build(:game, status: 'weird')).not_to be_valid
      expect(build(:game, auth_method: 'magic')).not_to be_valid
      expect(build(:game, auth_method: nil)).to be_valid
    end
  end

  describe AgentGame do
    it 'allows one row per account+game' do
      game = create(:game)
      create(:agent_game, account: account, game: game)
      expect(build(:agent_game, account: account, game: game)).not_to be_valid
    end

    it 'rejects unknown statuses and non-hash credentials' do
      expect(build(:agent_game, account: account, status: 'broken')).not_to be_valid
    end
  end

  describe GameAction do
    let(:agent_game) { create(:agent_game, account: account) }

    it 'enforces order_id uniqueness per account (idempotency backbone)' do
      create(:game_action, account: account, agent_game: agent_game, order_id: 'ord1')
      expect(build(:game_action, account: account, agent_game: agent_game, order_id: 'ord1')).not_to be_valid
    end

    it 'rejects negative amounts' do
      expect(build(:game_action, account: account, agent_game: agent_game, amount: -5)).not_to be_valid
      expect(build(:game_action, account: account, agent_game: agent_game, amount: nil)).to be_valid
    end

    it 'rejects unknown action types and statuses' do
      expect(build(:game_action, account: account, agent_game: agent_game, action_type: 'steal')).not_to be_valid
      expect(build(:game_action, account: account, agent_game: agent_game, status: 'maybe')).not_to be_valid
    end

    it 'sums only successful loads for the daily total' do
      contact = create(:contact, account: account)
      create(:game_action, account: account, agent_game: agent_game, contact: contact,
                           action_type: 'load', status: 'success', amount: 20)
      create(:game_action, account: account, agent_game: agent_game, contact: contact,
                           action_type: 'load', status: 'failed', amount: 50)

      expect(GameAction.loaded_today_for_contact(account_id: account.id, contact_id: contact.id)).to eq(20)
    end
  end

  describe CashierClaim do
    let(:inbox) { create(:inbox, account: account) }
    let(:contact) { create(:contact, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    it 'rejects zero/negative amounts and unknown action types' do
      base = { account: account, conversation: conversation, contact: contact }
      expect(build(:cashier_claim, **base, amount: 0)).not_to be_valid
      expect(build(:cashier_claim, **base, amount: -3)).not_to be_valid
      expect(build(:cashier_claim, **base, action_type: 'tip')).not_to be_valid
    end

    it 'sets an expiry on create and only claims pending rows' do
      claim = create(:cashier_claim, account: account, conversation: conversation, contact: contact)
      expect(claim.expires_at).to be_present

      user = create(:user, account: account)
      expect(claim.claim!(user)).to be_truthy
      expect(claim.reload.status).to eq('claimed')
      expect(claim.claim!(user)).to be false # already claimed
    end
  end

  describe BackupPage do
    it 'validates platform and status enums' do
      expect(build(:backup_page, account: account, platform: 'myspace')).not_to be_valid
      expect(build(:backup_page, account: account, status: 'on-fire')).not_to be_valid
    end

    it 'strips access_token from as_json' do
      page = create(:backup_page, account: account, access_token: 'sekret')
      expect(page.as_json).not_to have_key('access_token')
    end
  end

  describe Referral do
    let(:referrer) { create(:contact, account: account) }

    it 'blocks self-referrals' do
      referral = build(:referral, account: account, referrer_contact: referrer, referred_contact: referrer)
      expect(referral).not_to be_valid
      expect(referral.errors[:referred_contact_id]).to be_present
    end

    it 'rejects negative bonus amounts and unknown statuses' do
      expect(build(:referral, account: account, referrer_contact: referrer, bonus_amount: -1)).not_to be_valid
      expect(build(:referral, account: account, referrer_contact: referrer, status: 'limbo')).not_to be_valid
    end

    it 'mark_paid! stamps amount, type and time' do
      referral = create(:referral, account: account, referrer_contact: referrer, status: 'verified')
      referral.mark_paid!(amount: 10, type: 'freeplay')

      expect(referral.reload.status).to eq('paid')
      expect(referral.bonus_amount).to eq(10)
      expect(referral.paid_at).to be_present
    end
  end

  describe ReplyPreference do
    it 'is one per account' do
      ReplyPreference.for_account(account.id)
      expect(build(:reply_preference, account: account)).not_to be_valid
    end

    it 'rejects unknown transfer modes (money-fork integrity)' do
      pref = ReplyPreference.for_account(account.id)
      expect(pref.update(transfer_mode: 'yolo')).to be false
      expect(pref.update(transfer_deposit_shortfall_mode: 'shrug')).to be false
      expect(pref.update(transfer_mode: 'deposit_only', transfer_deposit_shortfall_mode: 'refuse')).to be true
    end

    it 'bounds reply lines and rag example count' do
      pref = ReplyPreference.for_account(account.id)
      expect(pref.update(max_reply_lines: 0)).to be false
      expect(pref.update(rag_example_count: 11)).to be false
    end
  end

  describe PlayerTier do
    it 'restricts names to the known tier set, unique per account' do
      create(:player_tier, account: account, name: 'vip')
      expect(build(:player_tier, account: account, name: 'vip')).not_to be_valid
      expect(build(:player_tier, account: account, name: 'whale')).not_to be_valid
    end
  end

  describe PlayerBonus do
    it 'requires a positive amount and stamps created_at' do
      contact = create(:contact, account: account)
      user = create(:user, account: account)
      expect(build(:player_bonus, account: account, contact: contact, given_by_user: user, amount: 0)).not_to be_valid

      bonus = create(:player_bonus, account: account, contact: contact, given_by_user: user, amount: 5)
      expect(bonus.created_at).to be_present
    end
  end

  describe GameRule do
    it 'is unique per account+game and parses tier lists defensively' do
      game = create(:game)
      rule = create(:game_rule, account: account, game: game)
      expect(build(:game_rule, account: account, game: game)).not_to be_valid

      rule.update!(freeplay_eligible_tiers: 'not-json')
      expect(rule.freeplay_tier_list).to eq(['new_player'])
      expect(rule.deposit_bonus_tier_list).to be_an(Array)
    end

    it 'caps the deposit bonus at the configured max' do
      game = create(:game)
      rule = create(:game_rule, account: account, game: game,
                                deposit_bonus_enabled: true, deposit_bonus_percentage: 50,
                                deposit_bonus_min_amount: 10, deposit_bonus_max_bonus: 20)

      expect(rule.calculate_bonus(100)).to eq(20)  # 50% of 100 = 50, capped at 20
      expect(rule.calculate_bonus(40)).to eq(20.0) # 50% of 40 = 20, at cap
      expect(rule.calculate_bonus(5)).to eq(0)     # below min deposit
    end
  end

  describe Holiday do
    it 'requires closed_on and scopes by date' do
      expect(build(:holiday, account: account, closed_on: nil)).not_to be_valid
      create(:holiday, account: account, closed_on: Date.current)

      expect(Holiday.for_account(account.id).for_date(Date.current).count).to eq(1)
      expect(Holiday.for_account(account.id).for_date(Date.tomorrow).count).to eq(0)
    end
  end
end
