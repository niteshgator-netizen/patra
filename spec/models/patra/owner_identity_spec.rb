# frozen_string_literal: true

require 'rails_helper'

# Patra PHASE 1 — workspace owner identity.
RSpec.describe 'Patra owner identity', type: :model do
  let(:account) { create(:account) }
  let(:creator) { create(:user) }
  let(:invited_admin) { create(:user) }

  describe 'Account#owner' do
    it 'returns the creator (administrator with inviter_id NULL)' do
      create(:account_user, account: account, user: creator, role: 'administrator')
      expect(account.owner).to eq(creator)
    end

    it 'does not pick a later-invited administrator over the creator' do
      create(:account_user, account: account, user: creator, role: 'administrator')
      create(:account_user, account: account, user: invited_admin, role: 'administrator', inviter: creator)
      expect(account.reload.owner).to eq(creator)
    end

    it 'falls back to the earliest administrator when none has a NULL inviter' do
      first_admin = create(:account_user, account: account, user: create(:user), role: 'administrator', inviter: creator)
      create(:account_user, account: account, user: create(:user), role: 'administrator', inviter: creator)
      expect(account.owner).to eq(first_admin.user)
    end

    it 'returns nil when the account has no administrators' do
      create(:account_user, account: account, user: creator, role: 'agent')
      expect(account.owner).to be_nil
    end
  end

  describe 'User#owner_of?' do
    before { create(:account_user, account: account, user: creator, role: 'administrator') }

    it 'is true for the creator' do
      expect(creator.owner_of?(account)).to be(true)
    end

    it 'is false for a later-invited administrator' do
      create(:account_user, account: account, user: invited_admin, role: 'administrator', inviter: creator)
      expect(invited_admin.owner_of?(account)).to be(false)
    end

    it 'is false for a blank account' do
      expect(creator.owner_of?(nil)).to be(false)
    end
  end
end
