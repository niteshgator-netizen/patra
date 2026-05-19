class SeedPanelGames < ActiveRecord::Migration[7.0]
  PANELS = [
    # Cluster 1 — ASP.NET panels (auth: session_cookie)
    { slug: 'milky_way',     name: 'Milky Way',      auth_method: 'session_cookie',
      api_base_url: 'https://milkywayapp.xyz:8781', domain: 'milkywayapp.xyz',
      agent_login_url: 'https://milkywayapp.xyz:8781/default.aspx',
      logo_emoji: '🌌', sort_order: 100,
      required_fields: [
        { 'name' => 'agent_username', 'label' => 'Agent username', 'type' => 'text' },
        { 'name' => 'asp_session_id', 'label' => 'ASP.NET_SessionId cookie', 'type' => 'password' }
      ] },
    { slug: 'fire_kirin',    name: 'Fire Kirin',     auth_method: 'session_cookie',
      api_base_url: 'https://firekirin.xyz:8888',  domain: 'firekirin.xyz',
      agent_login_url: 'https://firekirin.xyz:8888/default.aspx',
      logo_emoji: '🔥', sort_order: 101,
      required_fields: [
        { 'name' => 'agent_username', 'label' => 'Agent username', 'type' => 'text' },
        { 'name' => 'asp_session_id', 'label' => 'ASP.NET_SessionId cookie', 'type' => 'password' }
      ] },
    { slug: 'panda_master',  name: 'Panda Master',   auth_method: 'session_cookie',
      api_base_url: 'https://pandamaster.vip',     domain: 'pandamaster.vip',
      agent_login_url: 'https://pandamaster.vip/default.aspx',
      logo_emoji: '🐼', sort_order: 102,
      required_fields: [
        { 'name' => 'agent_username', 'label' => 'Agent username', 'type' => 'text' },
        { 'name' => 'asp_session_id', 'label' => 'ASP.NET_SessionId cookie', 'type' => 'password' }
      ] },
    { slug: 'orion_stars',   name: 'Orion Stars',    auth_method: 'session_cookie',
      api_base_url: 'https://orionstars.vip:8781', domain: 'orionstars.vip',
      agent_login_url: 'https://orionstars.vip:8781/default.aspx',
      logo_emoji: '⭐', sort_order: 103,
      required_fields: [
        { 'name' => 'agent_username', 'label' => 'Agent username', 'type' => 'text' },
        { 'name' => 'asp_session_id', 'label' => 'ASP.NET_SessionId cookie', 'type' => 'password' }
      ] },
    # Cluster 2 — Laravel panels (auth: bearer_jwt + session cookie)
    { slug: 'mafia',          name: 'Mafia',          auth_method: 'bearer_jwt',
      api_base_url: 'https://agentserver.mafia77777.com', domain: 'mafia77777.com',
      agent_login_url: 'https://agentserver.mafia77777.com/admin/login',
      logo_emoji: '🎭', sort_order: 200,
      required_fields: [
        { 'name' => 'bearer', 'label' => 'Bearer JWT', 'type' => 'password' },
        { 'name' => 'session_cookie', 'label' => 'Session cookie value', 'type' => 'password' },
        { 'name' => 'server_name_session', 'label' => 'server_name_session cookie', 'type' => 'password' }
      ] },
    { slug: 'game_room',      name: 'Gameroom',       auth_method: 'bearer_jwt',
      api_base_url: 'https://agentserver.gameroom777.com', domain: 'gameroom777.com',
      agent_login_url: 'https://agentserver.gameroom777.com/admin/login',
      logo_emoji: '🎮', sort_order: 201,
      required_fields: [
        { 'name' => 'bearer', 'label' => 'Bearer JWT', 'type' => 'password' },
        { 'name' => 'session_cookie', 'label' => 'Session cookie value', 'type' => 'password' },
        { 'name' => 'server_name_session', 'label' => 'server_name_session cookie', 'type' => 'password' }
      ] },
    { slug: 'cash_machine',   name: 'Cash Machine',   auth_method: 'bearer_jwt',
      api_base_url: 'https://agentserver.cashmachine777.com', domain: 'cashmachine777.com',
      agent_login_url: 'https://agentserver.cashmachine777.com/admin/login',
      logo_emoji: '💰', sort_order: 202,
      required_fields: [
        { 'name' => 'bearer', 'label' => 'Bearer JWT', 'type' => 'password' },
        { 'name' => 'session_cookie', 'label' => 'Session cookie value', 'type' => 'password' },
        { 'name' => 'server_name_session', 'label' => 'server_name_session cookie', 'type' => 'password' }
      ] },
    { slug: 'mr_all_in_one',  name: 'Mr All In One',  auth_method: 'bearer_jwt',
      api_base_url: 'https://agentserver.mrallinone777.com', domain: 'mrallinone777.com',
      agent_login_url: 'https://agentserver.mrallinone777.com/admin/login',
      logo_emoji: '🎯', sort_order: 203,
      required_fields: [
        { 'name' => 'bearer', 'label' => 'Bearer JWT', 'type' => 'password' },
        { 'name' => 'session_cookie', 'label' => 'Session cookie value', 'type' => 'password' },
        { 'name' => 'server_name_session', 'label' => 'server_name_session cookie', 'type' => 'password' }
      ] }
  ].freeze

  def up
    PANELS.each do |attrs|
      game = Game.find_or_initialize_by(slug: attrs[:slug])
      game.assign_attributes(attrs.merge(has_api: true, status: 'active'))
      game.save!
      puts "[seed] #{attrs[:slug]}: #{game.id} (#{game.persisted? ? 'updated' : 'created'})"
    end
  end

  def down
    PANELS.each do |attrs|
      Game.where(slug: attrs[:slug]).destroy_all
    end
  end
end
