class SeedGamesCatalog < ActiveRecord::Migration[7.1]
  def up
    games = [
      {
        slug: 'game_vault', name: 'Game Vault', logo_emoji: '🎰',
        domain: 'gamevault999.com',
        player_signup_url: 'https://download.gamevault999.com/',
        agent_login_url: 'https://agent.gamevault999.com',
        api_base_url: 'https://apius.gamevault999.com',
        has_api: true, auth_method: 'md5_token',
        required_fields: [
          { 'name' => 'agent_id', 'label' => 'Agent ID', 'type' => 'text', 'help' => 'From Game Vault → System Settings → agentid' },
          { 'name' => 'secret_key', 'label' => 'API Secret Key', 'type' => 'password', 'help' => 'From Game Vault → Download → API Secret Key' }
        ],
        description: 'Multi-game sweepstakes platform with fish games and slots.',
        sort_order: 10
      },
      { slug: 'orion_stars', name: 'Orion Stars', logo_emoji: '🌟', domain: 'orionstars.vip', sort_order: 20, description: 'Popular multi-title mobile sweepstakes platform.' },
      { slug: 'juwa', name: 'Juwa', logo_emoji: '🐉', domain: 'juwa777.com', sort_order: 30, description: 'Mobile fish games and slot sweepstakes.' },
      { slug: 'fire_kirin', name: 'Fire Kirin', logo_emoji: '🔥', domain: 'firekirin.com', sort_order: 40, description: 'Fish redemption arcade sweepstakes.' },
      { slug: 'milky_way', name: 'Milky Way', logo_emoji: '🌌', domain: 'milkywayapp.com', sort_order: 50, description: 'Mobile sweepstakes platform.' },
      { slug: 'vegas_sweeps', name: 'Vegas Sweeps', logo_emoji: '🎲', domain: 'vegassweeps.org', sort_order: 60, description: 'Vegas-style sweepstakes games.' },
      { slug: 'ultra_panda', name: 'Ultra Panda', logo_emoji: '🐼', domain: 'ultrapanda.mobi', sort_order: 70, description: 'Multi-game mobile sweepstakes.' },
      { slug: 'cash_frenzy', name: 'Cash Frenzy', logo_emoji: '💰', domain: 'cashfrenzy.app', sort_order: 80, description: 'Cash-themed mobile sweepstakes.' },
      { slug: 'panda_master', name: 'Panda Master', logo_emoji: '🐼', domain: 'pandamaster.vip', sort_order: 90, description: 'Panda-themed sweepstakes platform.' },
      { slug: 'river_sweeps', name: 'River Sweeps', logo_emoji: '🌊', domain: 'riversweeps.com', sort_order: 100, description: 'Multi-platform sweepstakes system.' },
      { slug: 'blue_dragon', name: 'Blue Dragon', logo_emoji: '🐲', domain: 'bluedragon.com', sort_order: 110, description: 'Dragon-themed sweepstakes platform.' },
      { slug: 'golden_dragon', name: 'Golden Dragon', logo_emoji: '🐉', domain: 'goldendragon.com', sort_order: 120, description: 'Golden dragon sweepstakes games.' },
      { slug: 'vegas_x', name: 'Vegas X', logo_emoji: '🎰', domain: 'vegasx.org', sort_order: 130, description: 'Vegas-style multi-game platform.' },
      { slug: 'magic_city', name: 'Magic City', logo_emoji: '🏙️', domain: 'magiccity.com', sort_order: 140, description: 'Magic-themed sweepstakes games.' },
      { slug: 'lightning_link', name: 'Lightning Link', logo_emoji: '⚡', domain: 'lightninglink.com', sort_order: 150, description: 'Lightning-themed slot sweepstakes.' },
      { slug: 'noble_sweeps', name: 'Noble Sweeps', logo_emoji: '👑', domain: 'noblesweeps.com', sort_order: 160, description: 'Premium sweepstakes platform.' },
      { slug: 'joker_mania', name: 'Joker Mania', logo_emoji: '🃏', domain: 'jokermania.com', sort_order: 170, description: 'Joker-themed sweepstakes games.' },
      { slug: 'game_room', name: 'Game Room', logo_emoji: '🎮', domain: 'gameroom.com', sort_order: 180, description: 'Multi-game sweepstakes platform.' },
      { slug: 'vblink', name: 'VBlink', logo_emoji: '💎', domain: 'vblink.com', sort_order: 190, description: 'Diamond-themed sweepstakes.' },
      { slug: 'golden_treasure', name: 'Golden Treasure', logo_emoji: '💰', domain: 'goldentreasure.com', sort_order: 200, description: 'Treasure-themed mobile games.' },
      { slug: 'mr_all_in_one', name: 'Mr All In One', logo_emoji: '🎯', domain: 'mrallinone.com', sort_order: 210, description: 'All-in-one sweepstakes platform.' },
      { slug: 'bit_play', name: 'BitPlay', logo_emoji: '🎲', domain: 'bitplay.com', sort_order: 220, description: 'Crypto-friendly sweepstakes.' },
      { slug: 'sirenis', name: 'Sirenis', logo_emoji: '🧜', domain: 'sirenis.com', sort_order: 230, description: 'Mermaid-themed sweepstakes.' },
      { slug: 'egame', name: 'eGame', logo_emoji: '🎮', domain: 'egame.com', sort_order: 240, description: 'Electronic gaming sweepstakes.' },
      { slug: 'cash_machine', name: 'Cash Machine', logo_emoji: '💵', domain: 'cashmachine.com', sort_order: 250, description: 'Cash-themed mobile sweepstakes.' }
    ]

    games.each do |attrs|
      game = Game.find_or_initialize_by(slug: attrs[:slug])
      game.assign_attributes(attrs.merge(status: 'active'))
      game.save!
    end
  end

  def down
    Game.where(slug: %w[
      game_vault orion_stars juwa fire_kirin milky_way vegas_sweeps ultra_panda
      cash_frenzy panda_master river_sweeps blue_dragon golden_dragon vegas_x
      magic_city lightning_link noble_sweeps joker_mania game_room vblink
      golden_treasure mr_all_in_one bit_play sirenis egame cash_machine
    ]).destroy_all
  end
end
