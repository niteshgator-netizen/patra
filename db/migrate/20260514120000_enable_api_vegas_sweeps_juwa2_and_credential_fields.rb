class EnableApiVegasSweepsJuwa2AndCredentialFields < ActiveRecord::Migration[7.1]
  GAME_VAULT_STYLE_FIELDS = [
    { 'name' => 'agent_id', 'type' => 'text' },
    { 'name' => 'secret_key', 'type' => 'password' },
    { 'name' => 'api_base_url', 'type' => 'text' }
  ].freeze

  def up
    game_vault = Game.find_by(slug: 'game_vault')
    game_vault&.update!(
      required_fields: GAME_VAULT_STYLE_FIELDS
    )

    juwa = Game.find_by(slug: 'juwa')
    juwa&.update!(
      required_fields: GAME_VAULT_STYLE_FIELDS
    )

    vegas = Game.find_by(slug: 'vegas_sweeps')
    vegas&.update!(
      player_signup_url: 'https://vegassweeps.org/',
      agent_login_url:   'https://vegassweeps.org/',
      api_base_url:      'https://apius.lasvegassweeps.com',
      has_api:           true,
      auth_method:       'md5_token',
      required_fields:   GAME_VAULT_STYLE_FIELDS
    )

    juwa2 = Game.find_by(slug: 'juwa_2')
    juwa2&.update!(
      player_signup_url: 'https://juwa2.com/',
      agent_login_url:   'https://juwa2.com/',
      api_base_url:      'https://apiinterface.juwa2.xin',
      has_api:           true,
      auth_method:       'md5_token',
      required_fields:   GAME_VAULT_STYLE_FIELDS
    )
  end

  def down
    Game.find_by(slug: 'game_vault')&.update!(
      required_fields: [
        { 'name' => 'agent_id', 'label' => 'Agent ID', 'type' => 'text',
          'help' => 'From Game Vault → System Settings → agentid' },
        { 'name' => 'secret_key', 'label' => 'API Secret Key', 'type' => 'password',
          'help' => 'From Game Vault → Download → API Secret Key' }
      ]
    )

    Game.find_by(slug: 'juwa')&.update!(
      required_fields: [
        { 'name' => 'agent_id', 'label' => 'Agent ID', 'type' => 'text', 'help' => 'From Juwa agent portal' },
        { 'name' => 'secret_key', 'label' => 'API Secret Key', 'type' => 'password', 'help' => 'From Juwa agent portal' }
      ]
    )

    Game.find_by(slug: 'vegas_sweeps')&.update!(
      has_api: false,
      auth_method: nil,
      api_base_url: nil,
      player_signup_url: nil,
      agent_login_url: nil,
      required_fields: []
    )

    Game.find_by(slug: 'juwa_2')&.update!(
      has_api: false,
      auth_method: nil,
      api_base_url: nil,
      player_signup_url: nil,
      agent_login_url: nil,
      required_fields: []
    )
  end
end
