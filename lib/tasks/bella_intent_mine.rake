# Labels the REAL customer intent on every BellaRagPair by reading the full
# exchange (prior turns + customer message + the cashier's ACTUAL reply) via Grok.
# SAFE: only writes the new real_intent / real_intent_confidence / real_intent_reason
# columns. Never edits customer_text, cashier_text, action_type, embedding, etc.
# RESUMABLE: re-run to continue where it stopped (only labels rows still NULL).
#
# Run full:  bundle exec rake bella:mine_intents
# Run trial: LIMIT=50 bundle exec rake bella:mine_intents
namespace :bella do
  desc 'Label real_intent on BellaRagPair from the full exchange via Grok'
  task mine_intents: :environment do
    require 'httparty'
    require 'json'

    xai_url    = 'https://api.x.ai/v1/chat/completions'
    model      = ENV.fetch('XAI_MODEL', 'grok-4.3')
    api_key    = ENV.fetch('XAI_API_KEY', '').to_s
    batch_size = (ENV['BATCH'] || 25).to_i
    limit      = ENV['LIMIT']&.to_i

    abort('XAI_API_KEY not set') if api_key.blank?

    taxonomy = <<~TAX
      Pick ONE label per item from the REAL situation shown by the cashier's reply
      and prior turns — NOT the surface keyword in the customer message.

      load_deposit              - paid money, wants it loaded
      load_freeplay             - wants free credits / free play, no payment
      load_bonus                - loading a bonus/promo they are owed
      replay_from_balance       - play again using existing balance, no new money
      cashout_redeem            - real withdrawal/redeem to cashapp/chime/paypal/venmo
      redeem_partial_replay     - cash out some, leave some to keep playing
      new_account_new_player    - brand new customer wants first account
      new_account_other_game    - existing customer wants account on a different game
      new_account_reissue       - needs new account because old one is broken/locked
      reset_password            - forgot/locked/forced password change
      payment_handle_request    - asking where to send / your chime/paypal/cashapp/venmo tag
      payment_sent_confirmation - says they sent it / shared receipt or screenshot
      status_check              - "is it loaded yet?" / "where's my cashout?"
      balance_check             - asking current balance/points
      whats_hitting             - asking which games are paying well
      referral                  - referring a friend / friend is a referral
      transfer_between_games    - move money/balance from one game to another
      tech_issue                - app/payment not working, can't send receipt
      complaint_angry           - angry/abusive/complaint — should go to a human
      greeting_chitchat         - hello/thanks/small talk only
      unclear                   - genuinely cannot tell — DO NOT guess

      If truly none fit, propose a short snake_case label. Prefer the list above.
    TAX

    system_prompt = "You label sweepstakes/gaming customer-service messages by the " \
      "REAL customer intent. Read the prior turns and the cashier's actual reply to " \
      "decide what really happened, ignoring the surface keyword.\n#{taxonomy}\n" \
      "Return ONLY a JSON array, one object per item: " \
      '[{"id":123,"intent":"load_deposit","confidence":"high","reason":"max 6 words"}]. ' \
      'confidence is high|medium|low. JSON only — no prose, no markdown.'

    relation = BellaRagPair.where(real_intent: nil).order(:id)
    relation = relation.limit(limit) if limit
    total = relation.count
    puts "[mine_intents] to label: #{total} (batch=#{batch_size}, model=#{model})"
    done = 0

    relation.in_batches(of: batch_size) do |group|
      items = group.map do |p|
        prev = Array(p.context_prev).map { |x| x.is_a?(Hash) ? x.values.join(': ') : x.to_s }.join(' | ')[0, 300]
        { id: p.id, prev: prev, customer: p.customer_text.to_s[0, 400], cashier: p.cashier_text.to_s[0, 400] }
      end

      begin
        resp = HTTParty.post(
          xai_url,
          headers: { 'Authorization' => "Bearer #{api_key}", 'Content-Type' => 'application/json' },
          body: {
            model: model,
            max_tokens: 1800,
            messages: [
              { role: 'system', content: system_prompt },
              { role: 'user',   content: "Label each item.\n#{JSON.generate(items)}" }
            ]
          }.to_json,
          timeout: 120
        )

        unless resp.success?
          puts "[mine_intents] HTTP #{resp.code} — skipping batch: #{resp.body.to_s[0, 200]}"
          next
        end

        raw = resp.parsed_response.dig('choices', 0, 'message', 'content').to_s.gsub(/```json|```/, '').strip
        by_id = {}
        JSON.parse(raw).each { |h| by_id[h['id'].to_i] = h }

        group.each do |p|
          h = by_id[p.id]
          next unless h
          p.update_columns(
            real_intent:            (h['intent'].to_s[0, 60].presence || 'unclear'),
            real_intent_confidence: (h['confidence'].to_s[0, 10].presence || 'low'),
            real_intent_reason:     h['reason'].to_s[0, 200]
          )
        end

        done += group.size
        puts "[mine_intents] progress #{done}/#{total}"
      rescue JSON::ParserError => e
        puts "[mine_intents] JSON parse fail — skipping batch: #{e.message}"
        next
      rescue StandardError => e
        puts "[mine_intents] error — skipping batch: #{e.class}: #{e.message}"
        next
      end

      sleep 0.3
    end

    puts "\n[mine_intents] DONE. Discovered buckets (real_intent → count):"
    BellaRagPair.where.not(real_intent: nil)
                .group(:real_intent).order(Arel.sql('count_all DESC')).count
                .each { |k, v| puts "  #{k}: #{v}" }
  end
end
