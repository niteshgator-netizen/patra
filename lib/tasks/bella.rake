namespace :bella do
  desc 'Seed bella_rag_pairs from a JSONL file (default: /tmp/bella_training/pairs.jsonl)'
  task seed_rag: :environment do
    input_path = ENV['PAIRS_FILE'] || '/tmp/bella_training/pairs.jsonl'

    unless File.exist?(input_path)
      puts "ERROR: input file not found at #{input_path}"
      puts "Set PAIRS_FILE=<path> or place pairs.jsonl at /tmp/bella_training/"
      exit 1
    end

    puts "Loading pairs from #{input_path}..."
    pairs = File.readlines(input_path).map { |line| JSON.parse(line) }
    puts "Loaded #{pairs.size} pairs."

    existing = BellaRagPair.count
    if existing.positive?
      puts "INFO: #{existing} bella_rag_pairs already exist. Will skip duplicates by embed_input."
    end

    success = 0
    failures = 0
    skipped = 0
    started_at = Time.now

    pairs.each_slice(128).with_index do |batch, batch_idx|
      texts = batch.map { |p| build_embed_input(p) }

      # Skip rows already in the DB (idempotent re-runs)
      missing_indexes = []
      texts.each_with_index do |t, i|
        if BellaRagPair.where(embed_input: t).exists?
          skipped += 1
        else
          missing_indexes << i
        end
      end

      next if missing_indexes.empty?

      to_embed = missing_indexes.map { |i| texts[i] }

      begin
        vectors = Bella::VoyageEmbedder.embed(to_embed, input_type: 'document')
      rescue Bella::VoyageEmbedder::EmbeddingError => e
        puts "  Batch #{batch_idx} EMBED FAILED: #{e.message}"
        failures += missing_indexes.size
        next
      end

      missing_indexes.each_with_index do |orig_i, vec_i|
        p = batch[orig_i]
        begin
          BellaRagPair.create!(
            customer_text: p['customer'].to_s[0, 4000],
            cashier_text:  p['cashier'].to_s[0, 4000],
            context_prev:  p['context_prev'] || [],
            cashier_names: p['cashier_names'] || Array(p['cashier_name']),
            page:          p['page'],
            ts_ms:         p['ts'],
            participant_count: p['participant_count'],
            embed_input:   texts[orig_i],
            embedding:     vectors[vec_i],
            embedding_model: 'voyage-3-lite',
            industry:      'sweepstakes',
            persona:       'bella',
          )
          success += 1
        rescue => e
          failures += 1
          puts "  Row insert failed: #{e.message}"
        end
      end

      if ((batch_idx + 1) % 10).zero?
        elapsed = (Time.now - started_at).to_i
        puts "  Progress: success=#{success} skipped=#{skipped} failed=#{failures} (#{elapsed}s elapsed)"
      end
    end

    elapsed = (Time.now - started_at).to_i
    puts ""
    puts "=" * 50
    puts "DONE in #{elapsed}s"
    puts "  Success: #{success}"
    puts "  Skipped: #{skipped} (already in DB)"
    puts "  Failed:  #{failures}"
    puts "  Total bella_rag_pairs in DB: #{BellaRagPair.count}"
    puts "=" * 50
  end

  desc 'Test retrieval: rake "bella:test_retrieval[load 20 to my juwa]"'
  task :test_retrieval, [:query] => :environment do |_t, args|
    q = args[:query] || 'load 20 to my juwa'
    puts "Query: #{q}"
    puts ""
    results = BellaRagPair.search_similar(q, limit: 5)
    if results.empty?
      puts "(no results — is the table seeded?)"
    else
      results.each_with_index do |r, i|
        puts "--- Result ##{i + 1} ---"
        puts "  [customer]: #{r.customer_text[0, 200]}"
        puts "  [cashier ]: #{r.cashier_text[0, 200]}"
        puts ""
      end
    end
  end

  def build_embed_input(pair)
    parts = []
    (pair['context_prev'] || []).each do |c|
      parts << "[#{c['role']}]: #{c['text']}"
    end
    parts << "[customer]: #{pair['customer']}"
    parts.join("\n")
  end

  desc 'Classify existing bella_rag_pairs.action_type via cashier_text regex heuristic'
  task backfill_action_type: :environment do
    # Cashout signals — cashier marked customer as PAID.
    # Matches: "Paid ✅", "Paid 50$✅", "paid✅", "Paid Don't forget", "we have paid"
    # Also: classic templates: "cashout approved", "cashed out", "cashing out", "remaining in game"
    # Excludes: customer-side reports like "you sent", "u sent", "haven't paid yet"
    cashout_re = /
      \b(?:
        cashout\s+(?:approved|of|request)|
        cash(?:ed|ing)\s+out|
        remaining\s+in\s+game|
        paid\s*\d+\s*\$?\s*[✅️]|     # "Paid 17✅️"
        paid\s*[✅️]|                  # "Paid ✅"
        \bpaid\b\s*$|                  # "Paid" at end of segment
        we\s+(?:have\s+)?paid|
        \bpaid\s+(?:half|don['']?t|please|refer)
      )
    /ix.freeze

    # Account-handoff signals — cashier delivered credentials.
    # Patterns:
    #   "<username><gamesuffix> Same username and password"
    #   "<username><gamesuffix> Same id pw"
    #   "Account: foo Password: bar"
    #   "Username: foo Password: bar"
    #   "Creating <username>"
    # Excludes: PayPal/email payment templates that mention "Paypal username"
    account_re = /
      (?:
        \bsame\s+(?:user\s*name|username|id)\s+(?:and\s+)?(?:password|pw)\b|
        ^\s*(?:account|username|user)\s*:\s*\S|
        \npassword\s*:\s*\S|
        \bcreating\s+\w{4,}\s|
        \bcreated\s+(?:account|user)|
        \byour\s+username\s+is\s+\S
      )
    /ix.freeze

    # Load signals — cashier loaded money to game. Broadened patterns.
    # Catches: "Loaded ✅", "Loaded 20 dear", "Loaded $25", "Loaded 10 to bethany1jw",
    #          "Loading fp ✅", "fp ✅loaded", "added 20 to jw", "credited 50", "topped up"
    # Excludes: "you loaded" (customer-side, no following game-suffix), "haven't loaded yet" (negation context)
    load_re = /
      \b(?:
        load(?:ed|ing)\s*\$?\d+ |                                                                    # "Loaded 20", "Loaded $25"
        load(?:ed|ing)\s*[✅️] |                                                                       # "Loaded ✅"
        [✅️]\s*load(?:ed|ing) |                                                                       # "✅loaded"
        load(?:ed|ing)\s+(?:to|for|on|in|him|her|them|dear|love|hun|bro) |                            # "Loaded 10 to ..."
        load(?:ed|ing)\s+\w+(?:_)?(?:jw2?|fk|mw|os|gv|cm|up|mk1|ma|pm|gr|fp|gp|mf)\b |                # "loaded bethany1jw"
        (?:fp|gp|jw2?|fk|mw|os|gv|cm|up|mk1|ma|pm)\s*[✅️]?\s*load(?:ed|ing) |                          # "fp loaded", "fp ✅loaded"
        just\s+load(?:ed|ing) |                                                                       # "just loaded"
        credited\s+\$?\d |                                                                            # "credited 50"
        topped?\s+up(?:\s*\$?\d+)? |                                                                  # "topped up", "topped up 20"
        recharged?\s+\$?\d |                                                                          # "recharged 20"
        added\s+\$?\d+\s+(?:to|in|on)\b |                                                             # "added 20 to jw"
        put\s+\$?\d+\s+(?:in|on|to)\b                                                                 # "put 20 in fp"
      )
    /ix.freeze

    # Password reset signals.
    reset_re = /
      \b(?:
        reset(?:\s+(?:the\s+)?(?:pw|password))?|
        new\s+(?:pw|password)\s+(?:is|:)|
        password\s+reset\s+to|
        just\s+reset\s+(?:the\s+)?(?:pw|password)
      )\b
    /ix.freeze

    total = BellaRagPair.count
    puts "Scanning #{total} rows..."

    counts = Hash.new(0)
    started = Time.now

    BellaRagPair.find_each(batch_size: 500).with_index do |pair, i|
      text = pair.cashier_text.to_s
      type =
        if text.match?(cashout_re) then 'cashout'
        elsif text.match?(account_re) then 'account'
        elsif text.match?(load_re) then 'load'
        elsif text.match?(reset_re) then 'reset'
        else nil
        end

      if pair.action_type != type
        pair.update_column(:action_type, type)
        counts[type || 'chitchat'] += 1
      end

      if (i + 1) % 2000 == 0
        puts "  scanned #{i + 1}/#{total} (#{(Time.now - started).to_i}s elapsed)"
      end
    end

    puts ""
    puts "=" * 50
    puts "DONE in #{(Time.now - started).to_i}s"
    counts.each { |k, v| puts "  #{k}: #{v}" }
    puts "  Total chitchat in DB now: #{BellaRagPair.where(action_type: nil).count}"
    puts "  Total actions  in DB now: #{BellaRagPair.where.not(action_type: nil).count}"
    puts "=" * 50
  end
end
