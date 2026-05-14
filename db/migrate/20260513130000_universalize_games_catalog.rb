class UniversalizeGamesCatalog < ActiveRecord::Migration[7.1]
  def up
    # Juwa: now API-enabled
    juwa = Game.find_by(slug: 'juwa')
    juwa&.update!(
      player_signup_url: 'https://dl.juwa777.com/',
      agent_login_url:   'https://ht.juwa777.com/login',
      api_base_url:      'https://ht.juwa777.com',
      has_api:           true,
      auth_method:       'md5_token',
      required_fields: [
        { 'name' => 'agent_id',  'label' => 'Agent ID',       'type' => 'text',     'help' => 'From Juwa agent portal' },
        { 'name' => 'secret_key','label' => 'API Secret Key', 'type' => 'password', 'help' => 'From Juwa agent portal' }
      ]
    )

    # 7 new games requested
    new_games = [
      { slug: 'spin_city',     name: 'Spin City',     logo_emoji: '🎡', domain: 'spincity.com',     sort_order: 260, description: 'City-themed slot sweepstakes.' },
      { slug: 'mafia',         name: 'Mafia',         logo_emoji: '🎩', domain: 'mafia.com',        sort_order: 270, description: 'Mafia-themed sweepstakes platform.' },
      { slug: 'billion_balls', name: 'Billion Balls', logo_emoji: '⚽', domain: 'billionballs.com', sort_order: 280, description: 'Ball-game sweepstakes platform.' },
      { slug: 'yolo',          name: 'Yolo',          logo_emoji: '🎉', domain: 'yolo.com',         sort_order: 290, description: 'High-energy sweepstakes games.' },
      { slug: 'vegas_roll',    name: 'Vegas Roll',    logo_emoji: '🎲', domain: 'vegasroll.com',    sort_order: 300, description: 'Vegas dice and slots sweepstakes.' },
      { slug: 'juwa_2',        name: 'Juwa 2.0',      logo_emoji: '🐉', domain: 'juwa2.com',        sort_order: 310, description: 'Juwa next-gen sweepstakes platform.' }
    ]

    new_games.each do |attrs|
      game = Game.find_or_initialize_by(slug: attrs[:slug])
      game.assign_attributes(attrs.merge(status: 'active'))
      game.save!
    end
  end

  def down
    Game.where(slug: %w[spin_city mafia billion_balls yolo vegas_roll juwa_2]).destroy_all
  end
end
