# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# PATRA BALANCE PROBE (F18) — capture the raw evidence for the Juwa +
# Panda Master "connect OK / balance empty" diagnosis. READ-ONLY: only
# balance/search reads, zero loads, zero cashouts, zero player writes.
#
#   RUN (Render Shell):  bundle exec rails runner script/patra_balance_probe.rb
#   other slugs:         SLUGS=juwa,panda_master,game_vault bundle exec rails runner ...
#
# What it prints per game:
#   Juwa-style JSON clients  → the RAW agentBalance response body (keys+values)
#                              so we can see which key actually carries balance.
#   ASP.NET scrape clients   → whether 'updateBalance(' exists in the page and
#                              the exact 120-char snippet around it, plus what
#                              the current regex extracts. Shows format drift
#                              (e.g. thousands separators) immediately.
# ─────────────────────────────────────────────────────────────────────────────

ACCOUNT_ID = ENV.fetch('PROBE_ACCOUNT_ID', '2').to_i
slugs = ENV.fetch('SLUGS', 'juwa,panda_master,game_vault,orion_stars').split(',').map(&:strip)

account = Account.find(ACCOUNT_ID)

slugs.each do |slug|
  puts "\n#{'=' * 70}\nGAME: #{slug}"
  ag = account.agent_games.joins(:game).where(games: { slug: slug }, status: 'active').first ||
       account.agent_games.joins(:game).where(games: { slug: slug }).first
  unless ag
    puts '  no agent_game configured — skipped'
    next
  end

  client = Games::ClientRegistry.client_for(ag)
  unless client
    puts '  no client in registry — skipped'
    next
  end
  puts "  client=#{client.class.name}"

  # 1) the normal path every caller uses
  begin
    bal = client.agent_balance
    puts "  agent_balance() => #{bal.inspect[0, 400]}"
  rescue StandardError => e
    puts "  agent_balance() RAISED #{e.class}: #{e.message[0, 200]}"
  end

  # 2) evidence capture per client family
  begin
    if client.is_a?(Games::Juwa::Client) || (defined?(Games::Juwa2::Client) && client.is_a?(Games::Juwa2::Client))
      raw = client.send(:raw_post, 'agentBalance', {})
      if raw.is_a?(Hash)
        puts "  RAW agentBalance body: #{raw.inspect[0, 600]}"
        data = raw['data']
        puts "  data keys: #{data.is_a?(Hash) ? data.keys.inspect : data.class}"
        puts "  dig('data','agent_balance') => #{raw.dig('data', 'agent_balance').inspect}  <- what the code reads (juwa/client.rb:147)"
      else
        puts "  RAW agentBalance non-hash: #{raw.inspect[0, 300]}"
      end
    elsif defined?(Games::AspNetPanel::BaseClient) && client.is_a?(Games::AspNetPanel::BaseClient)
      resp = client.send(:http_request, :get, client.send(:search_url),
                         headers: client.send(:nav_headers, referer: client.send(:search_url)))
      body = client.send(:response_body_utf8, resp)
      puts "  search page bytes=#{body.to_s.bytesize}"
      idx = body.to_s.index('updateBalance(')
      if idx
        snippet = body[[idx - 20, 0].max, 140].to_s.gsub(/\s+/, ' ')
        puts "  updateBalance snippet: #{snippet.inspect}"
        m = body.match(/updateBalance\("Balance:([\d.]+)"\)/)
        puts "  current regex /updateBalance\\(\"Balance:([\\d.]+)\"\\)/ => #{m ? m[1].inspect : 'NO MATCH  <- this is the blank-balance cause if snippet shows another format'}"
      else
        puts "  'updateBalance(' NOT in page — layout changed or session/page wrong (first 200 chars: #{body.to_s[0, 200].gsub(/\s+/, ' ').inspect})"
      end
    else
      puts '  (no extra raw capture implemented for this client family)'
    end
  rescue StandardError => e
    puts "  raw capture failed: #{e.class}: #{e.message[0, 200]}"
  end
end

puts "\nPROBE COMPLETE — read-only, nothing modified."
