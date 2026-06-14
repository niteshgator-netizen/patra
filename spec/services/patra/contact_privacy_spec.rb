# frozen_string_literal: true

require 'rails_helper'

# Patra PHASE 6 — name-privacy chokepoint.
# WALL-LOCAL-UNRUNNABLE locally: needs Rails boot. Run on the Render shell:
#   bundle exec rspec spec/services/patra/contact_privacy_spec.rb
RSpec.describe Patra::ContactPrivacy do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: 'John Dorian') }
  # The first administrator created (inviter NULL, lowest id) is the workspace owner.
  let!(:owner_au) { create(:account_user, account: account, user: create(:user), role: 'administrator') }

  def member(role:, permissions: nil, inviter: nil)
    au = create(:account_user, account: account, user: create(:user), role: role, inviter: inviter)
    au.update!(custom_role: create(:custom_role, account: account, permissions: permissions)) if permissions
    au
  end

  it 'shows the full name to the owner' do
    expect(described_class.display_name(contact, owner_au)).to eq('John Dorian')
  end

  it 'shows the full name to a non-owner administrator' do
    admin_au = member(role: 'administrator', inviter: owner_au.user)
    expect(described_class.display_name(contact, admin_au)).to eq('John Dorian')
  end

  it 'shows the full name when the role has contact_pii_full' do
    au = member(role: 'agent', permissions: ['contact_pii_full'])
    expect(described_class.display_name(contact, au)).to eq('John Dorian')
  end

  it 'hides the name to "Player" when the role has contact_pii_hidden' do
    au = member(role: 'agent', permissions: ['contact_pii_hidden'])
    expect(described_class.display_name(contact, au)).to eq('Player')
  end

  it 'shows first-name-only by default (no pii key)' do
    au = member(role: 'agent', permissions: ['contact_manage'])
    expect(described_class.display_name(contact, au)).to eq('John')
  end

  it 'shows first-name-only for an agent with no custom_role' do
    au = member(role: 'agent')
    expect(described_class.display_name(contact, au)).to eq('John')
  end

  it 'returns "Player" for a blank contact name' do
    blank = create(:contact, account: account, name: '')
    au = member(role: 'agent', permissions: ['contact_manage'])
    expect(described_class.display_name(blank, au)).to eq('Player')
  end

  it 'returns the full name when account_user is nil (system/webhook context)' do
    expect(described_class.display_name(contact, nil)).to eq('John Dorian')
  end
end
