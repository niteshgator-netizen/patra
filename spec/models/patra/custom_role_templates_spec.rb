# frozen_string_literal: true

require 'rails_helper'

# Patra PHASE 3 — role template validity.
RSpec.describe CustomRoleTemplates do
  it 'references only valid CustomRole permissions in every template' do
    CustomRoleTemplates::TEMPLATES.each do |template|
      invalid = template[:permissions] - CustomRole::PERMISSIONS
      expect(invalid).to be_empty, "template #{template[:key]} has invalid perms: #{invalid.inspect}"
    end
  end

  it 'reports valid? => true' do
    expect(described_class.valid?).to be(true)
  end

  it 'exposes the five expected templates with unique keys' do
    keys = CustomRoleTemplates::TEMPLATES.map { |t| t[:key] }
    expect(keys).to contain_exactly('manager', 'support', 'accountant', 'cashier', 'custom')
  end

  it 'gives the custom template a blank permission set' do
    custom = CustomRoleTemplates::TEMPLATES.find { |t| t[:key] == 'custom' }
    expect(custom[:permissions]).to eq([])
  end

  # Patra (A3) — six-tier vocabulary (additive to the five starting-point templates above).
  it 'exposes all six role tiers in canonical order' do
    expect(CustomRoleTemplates.tier_keys).to eq(%w[owner admin manager cashier agent viewer])
  end

  it 'reports tiers_valid? => true' do
    expect(CustomRoleTemplates.tiers_valid?).to be(true)
  end

  it 'marks the owner tier implicit, permanent and non-removable' do
    owner = CustomRoleTemplates.tier('owner')
    expect(owner[:kind]).to eq('implicit')
    expect(owner[:removable]).to be(false)
  end

  it 'references only valid CustomRole permissions in every tier default' do
    CustomRoleTemplates::TIERS.each do |tier|
      invalid = Array(tier[:default_permissions]) - CustomRole::PERMISSIONS
      expect(invalid).to be_empty, "tier #{tier[:key]} has invalid perms: #{invalid.inspect}"
    end
  end

  it 'grants the manager template message_edit_delete (so the Manager tier may edit/delete)' do
    manager = CustomRoleTemplates::TEMPLATES.find { |t| t[:key] == 'manager' }
    expect(manager[:permissions]).to include('message_edit_delete')
  end
end
