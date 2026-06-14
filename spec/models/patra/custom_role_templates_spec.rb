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
end
