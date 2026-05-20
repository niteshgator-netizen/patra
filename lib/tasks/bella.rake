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
end
