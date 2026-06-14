# frozen_string_literal: true

require 'rails_helper'

# Patra PHASE 4 (R6) — view_all_inboxes overlay on User#assigned_inboxes.
# Proves all four cases: admin->all (unchanged), agent+view_all_inboxes->all,
# agent without->membership (unchanged), agent with no custom_role->membership (unchanged).
RSpec.describe 'Patra all-inbox access (User#assigned_inboxes)', type: :model do
  let(:account) { create(:account) }
  let!(:inbox_a) { create(:inbox, account: account) }
  let!(:inbox_b) { create(:inbox, account: account) }

  around do |example|
    Current.account = account
    example.run
    Current.account = nil
  end

  def add_member(user, inbox)
    create(:inbox_member, user: user, inbox: inbox)
  end

  it 'admin sees every inbox (default unchanged)' do
    admin = create(:user)
    create(:account_user, account: account, user: admin, role: 'administrator')
    expect(admin.assigned_inboxes).to match_array([inbox_a, inbox_b])
  end

  it 'agent with view_all_inboxes sees every inbox (overlay)' do
    agent = create(:user)
    role = create(:custom_role, account: account, permissions: ['view_all_inboxes'])
    create(:account_user, account: account, user: agent, role: 'agent', custom_role: role)
    expect(agent.assigned_inboxes).to match_array([inbox_a, inbox_b])
  end

  it 'agent without view_all_inboxes sees only its membership inboxes' do
    agent = create(:user)
    role = create(:custom_role, account: account, permissions: ['contact_manage'])
    create(:account_user, account: account, user: agent, role: 'agent', custom_role: role)
    add_member(agent, inbox_a)
    expect(agent.assigned_inboxes).to match_array([inbox_a])
  end

  it 'agent with no custom_role sees only its membership inboxes (default unchanged)' do
    agent = create(:user)
    create(:account_user, account: account, user: agent, role: 'agent')
    add_member(agent, inbox_b)
    expect(agent.assigned_inboxes).to match_array([inbox_b])
  end
end
