# frozen_string_literal: true

# Factories for the Patra vertical models (games, money ops, claims, referrals).
FactoryBot.define do
  factory :game do
    sequence(:name) { |n| "Test Game #{n}" }
    sequence(:slug) { |n| "test_game_#{n}" }
    has_api { true }
    status { 'active' }
    auth_method { 'md5_token' }
    required_fields { [] }
  end

  factory :agent_game do
    account
    game
    status { 'active' }
    credentials { { 'agent_id' => '12345', 'secret_key' => 'test_secret_key' } }
    ip_whitelist_confirmed { true }
  end

  factory :game_action do
    account
    agent_game
    action_type { 'load' }
    sequence(:order_id) { |n| "pat_test#{n}_#{n}" }
    status { 'pending' }
    amount { 25.0 }
    game_username { 'player_one' }
  end

  factory :cashier_claim do
    account
    conversation
    contact
    action_type { 'load' }
    amount { 20.0 }
    status { 'pending' }
  end

  factory :backup_page do
    account
    platform { 'facebook' }
    sequence(:page_id) { |n| "1000#{n}" }
    page_name { 'Backup Page' }
    access_token { 'fb_page_token_secret' }
    status { 'standby' }
  end

  factory :referral do
    account
    association :referrer_contact, factory: :contact
    status { 'pending' }
  end

  factory :reply_preference do
    account
  end

  factory :game_rule do
    account
    game
  end

  factory :player_tier do
    account
    name { 'regular' }
  end

  factory :player_bonus do
    account
    contact
    association :given_by_user, factory: :user
    amount { 10.0 }
  end

  factory :holiday do
    account
    closed_on { Date.current }
    name { 'Test Holiday' }
  end
end
