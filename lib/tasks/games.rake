# rake games:inspect_login[milky_way]
# rake games:inspect_login[fire_kirin]
# rake games:inspect_login[panda_master]
# rake games:inspect_login[orion_stars]
#
# Phase 1a — diagnostic task. Fetches the agent login page and dumps
# all form structure to console. Does NOT log in. Does NOT touch DB.
# Used once to confirm field names before building the real refresh in 1b.

require 'net/http'
require 'uri'

namespace :games do
  desc 'Inspect login page structure for a Cluster 1 ASP.NET panel'
  task :inspect_login, [:slug] => :environment do |_t, args|
    slug = args[:slug].to_s.strip
    if slug.blank?
      puts 'ERROR: usage: rake games:inspect_login[milky_way]'
      exit 1
    end

    # Hardcoded BASE_URLs for Cluster 1 (mirrors app/services/games/<slug>/client.rb)
    base_urls = {
      'milky_way'    => 'https://milkywayapp.xyz:8781',
      'fire_kirin'   => 'https://firekirin.xyz:8888',
      'panda_master' => 'https://pandamaster.vip',
      'orion_stars'  => 'https://orionstars.vip:8781'
    }

    base_url = base_urls[slug]
    if base_url.nil?
      puts "ERROR: unknown slug '#{slug}'. Supported: #{base_urls.keys.join(', ')}"
      exit 1
    end

    # The login page is typically the root URL — ASP.NET redirects unauthenticated
    # visitors to default.aspx. We hit the BASE_URL directly and follow redirects.
    target_url = "#{base_url}/"
    puts "[inspect_login] target=#{target_url}"
    puts ''

    user_agent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' \
                 '(KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36'

    headers = {
      'User-Agent' => user_agent,
      'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
      'Accept-Language' => 'en-US,en;q=0.9',
      'Sec-Ch-Ua' => '"Google Chrome";v="145", "Not.A/Brand";v="8", "Chromium";v="145"',
      'Sec-Ch-Ua-Mobile' => '?0',
      'Sec-Ch-Ua-Platform' => '"Windows"',
      'Sec-Fetch-Dest' => 'document',
      'Sec-Fetch-Mode' => 'navigate',
      'Sec-Fetch-Site' => 'none',
      'Upgrade-Insecure-Requests' => '1'
    }

    uri = URI(target_url)
    response = nil
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                    open_timeout: 10, read_timeout: 25) do |http|
      req = Net::HTTP::Get.new(uri.request_uri)
      headers.each { |k, v| req[k] = v }
      response = http.request(req)
    end

    puts "=== RESPONSE STATUS ==="
    puts "HTTP #{response.code} #{response.message}"
    puts ''

    puts "=== RESPONSE HEADERS (Set-Cookie + Location) ==="
    response.each_header do |k, v|
      if k.downcase.match?(/set-cookie|location|content-type/)
        puts "#{k}: #{v}"
      end
    end
    puts ''

    body = response.body.to_s

    puts "=== BODY LENGTH ==="
    puts "#{body.bytesize} bytes"
    puts ''

    puts "=== FORM TAG (action + method) ==="
    form_match = body.match(/<form[^>]*>/i)
    if form_match
      puts form_match[0]
    else
      puts '(no <form> tag found)'
    end
    puts ''

    puts "=== ALL <INPUT> FIELDS ==="
    body.scan(/<input[^>]*>/i).each_with_index do |inp, i|
      name = inp.match(/\bname=["']([^"']+)["']/i)&.[](1)
      type = inp.match(/\btype=["']([^"']+)["']/i)&.[](1) || 'text'
      id   = inp.match(/\bid=["']([^"']+)["']/i)&.[](1)
      val  = inp.match(/\bvalue=["']([^"']*)["']/i)&.[](1)
      val_preview = val.to_s.length > 60 ? "#{val[0..40]}...(#{val.length} chars)" : val
      puts "#{format('%02d', i + 1)}. name=#{name.inspect} type=#{type.inspect} id=#{id.inspect} value=#{val_preview.inspect}"
    end
    puts ''

    puts "=== ALL <IMG> URLs (CAPTCHA candidates) ==="
    body.scan(/<img[^>]*>/i).each_with_index do |img, i|
      src = img.match(/\bsrc=["']([^"']+)["']/i)&.[](1)
      alt = img.match(/\balt=["']([^"']*)["']/i)&.[](1)
      id  = img.match(/\bid=["']([^"']+)["']/i)&.[](1)
      puts "#{format('%02d', i + 1)}. src=#{src.inspect} id=#{id.inspect} alt=#{alt.inspect}"
    end
    puts ''

    puts "=== HTML SNIPPET around 'code' or 'captcha' or 'verify' ==="
    ['code', 'captcha', 'verify', 'validate'].each do |keyword|
      idx = body.downcase.index(keyword)
      next if idx.nil?

      start = [idx - 100, 0].max
      finish = [idx + 200, body.length].min
      snippet = body[start...finish].gsub(/\s+/, ' ')
      puts "-- '#{keyword}' found at byte #{idx}:"
      puts "   ...#{snippet}..."
    end
    puts ''

    puts "[inspect_login] done. Use this output to identify:"
    puts "  - the FORM action URL (where login POST goes)"
    puts "  - the username field name (likely contains 'user', 'account', 'name')"
    puts "  - the password field name (likely contains 'pass', 'pwd')"
    puts "  - the CAPTCHA input field name (likely contains 'code', 'verify', 'captcha')"
    puts "  - the CAPTCHA image src URL"
    puts "  - the submit button event target"
  end

  desc 'Refresh agent session for a Cluster 1 ASP.NET panel (e.g. milky_way)'
  task :refresh_session, [:slug] => :environment do |_t, args|
    slug = args[:slug].to_s.strip
    if slug.blank?
      puts 'ERROR: usage: rake "games:refresh_session[milky_way]"'
      exit 1
    end

    unless Games::AspNetPanel::SessionRefresher::BASE_URLS.key?(slug)
      puts "ERROR: slug '#{slug}' not supported. Supported: #{Games::AspNetPanel::SessionRefresher::BASE_URLS.keys.join(', ')}"
      exit 1
    end

    ag = AgentGame.joins(:game).where(games: { slug: slug }).first
    if ag.nil?
      puts "ERROR: AgentGame for slug '#{slug}' not found in DB"
      exit 1
    end

    puts "[refresh_session] starting for slug=#{slug} agent_username=#{ag.credentials['agent_username']}"
    puts "[refresh_session] current asp_session_id length=#{ag.credentials['asp_session_id'].to_s.length}"
    puts ''

    refresher = Games::AspNetPanel::SessionRefresher.new(ag)
    result = refresher.refresh!

    puts ''
    puts "=== RESULT ==="
    puts result.inspect

    if result[:ok]
      puts ''
      puts "✅ SUCCESS. New asp_session_id stored (length=#{result[:new_session_id].length}). Attempts=#{result[:attempts]}. Fallback=#{result[:fallback] || false}"
      exit 0
    else
      puts ''
      puts "❌ FAILED. #{result[:error]}"
      exit 1
    end
  end
end
