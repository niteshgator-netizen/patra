# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# PATRA PANDA PROBE (H7) — diagnose the Panda Master "session OK / AccountsList
# 301 + 0-byte body / balance nil" symptom, with orion_stars as the healthy
# control. READ-ONLY: plain GETs with the stored session cookie; zero writes,
# zero loads, zero player actions, no session refresh triggered.
#
#   RUN (Render Shell):  bundle exec rails runner script/patra_panda_probe.rb
#   other slugs:         SLUGS=panda_master,orion_stars,milky_way,fire_kirin \
#                        bundle exec rails runner script/patra_panda_probe.rb
#
# Per slug × endpoint it prints: HTTP status, Location header, body length,
# __VIEWSTATE / updateBalance / txtLoginName markers — then manually follows up
# to 3 redirects printing every hop and the final landing page. The Location
# header of the first 301 is THE deciding fact: same-host scheme/path bounce
# (H7 client fix handles it) vs moved host/port (BASE_URL needs updating).
# ─────────────────────────────────────────────────────────────────────────────

require 'net/http'
require 'uri'

ACCOUNT_ID = ENV.fetch('PROBE_ACCOUNT_ID', '2').to_i
SLUGS = ENV.fetch('SLUGS', 'panda_master,orion_stars').split(',').map(&:strip)
MAX_HOPS = 3

UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' \
     '(KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36'

def headers_for(session_id, referer)
  h = {
    'User-Agent' => UA,
    'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language' => 'en-US,en;q=0.9',
    'Upgrade-Insecure-Requests' => '1',
    'Referer' => referer
  }
  h['Cookie'] = "ASP.NET_SessionId=#{session_id}" unless session_id.to_s.empty?
  h
end

def single_get(url, session_id)
  uri = URI(url)
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                  open_timeout: 10, read_timeout: 25) do |http|
    req = Net::HTTP::Get.new(uri.request_uri)
    headers_for(session_id, url).each { |k, v| req[k] = v }
    http.request(req)
  end
end

def describe(response)
  body = response.body.to_s
  markers = []
  markers << 'VIEWSTATE' if body.include?('__VIEWSTATE')
  markers << 'updateBalance' if body.include?('updateBalance(')
  markers << 'LOGIN-FORM(txtLoginName)' if body.include?('txtLoginName')
  loc = response['Location'].to_s
  "status=#{response.code} body_len=#{body.length} location=#{loc.empty? ? '-' : loc} markers=[#{markers.join(',')}]"
end

account = Account.find(ACCOUNT_ID)

SLUGS.each do |slug|
  puts "\n#{'=' * 72}\nSLUG: #{slug}"

  ag = account.agent_games.joins(:game).where(games: { slug: slug }, status: 'active').first ||
       account.agent_games.joins(:game).where(games: { slug: slug }).first
  unless ag
    puts '  no agent_game configured — skipped'
    next
  end

  base = Games::AspNetPanel::SessionRefresher::BASE_URLS[slug]
  unless base
    puts "  not an AspNetPanel slug (no BASE_URL) — skipped"
    next
  end

  session_id = ag.credentials.to_h['asp_session_id'].to_s
  puts "  base_url=#{base} session_id_present=#{!session_id.empty?} (len=#{session_id.length})"

  endpoints = {
    'root' => "#{base}/",
    'AccountsList' => "#{base}/Module/AccountManager/AccountsList.aspx"
  }

  endpoints.each do |label, url|
    puts "  -- #{label}: GET #{url}"
    begin
      response = single_get(url, session_id)
      puts "     #{describe(response)}"

      hops = 0
      current_url = url
      while response.is_a?(Net::HTTPRedirection) && hops < MAX_HOPS
        raw_loc = response['Location'].to_s
        break if raw_loc.empty?

        hops += 1
        current_url = URI.join(current_url, raw_loc).to_s
        puts "     hop#{hops} -> GET #{current_url}"
        response = single_get(current_url, session_id)
        puts "     #{describe(response)}"
      end
      puts "     FINAL url=#{current_url}" if hops.positive?
    rescue StandardError => e
      puts "     ERROR #{e.class}: #{e.message}"
    end
  end
end

puts "\nINTERPRETATION:"
puts '- AccountsList 301 whose Location is SAME host (scheme/path bounce): the H7'
puts '  base_client fix follows it once — balance should come back on its own.'
puts '- Location pointing at a DIFFERENT host/port: update BASE_URL in'
puts '  app/services/games/panda_master/client.rb AND SessionRefresher::BASE_URLS.'
puts '- Location at default.aspx or root: session is actually dead for that page;'
puts '  the reactive refresh path owns it.'
puts '- Marker LOGIN-FORM on the final page: cookie not accepted — session invalid.'
