# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# CHANGE 1 APPLIER — RAG copy-paste leak fix for app/services/ai/reply_service.rb
#
# WHY THIS FILE EXISTS: reply_service.rb is a protected hot file (deny-listed in
# .claude/settings.json), so Claude Code cannot edit it directly. This script
# applies the reviewed Change 1 edits with exact-anchor string replacement.
# Genius runs it ONCE, locally:
#
#   RUN (PowerShell, repo root):   ruby script/apply_change1_rag_leak.rb
#   THEN VERIFY:                   ruby -c app/services/ai/reply_service.rb
#
# WHAT IT CHANGES (7 surgical edits, all inside reply_service.rb):
#   1. SYSTEM_PROMPT: "follow their style and actions exactly" -> style yes,
#      other customers' names/usernames/amounts never.
#   2. SYSTEM_PROMPT RAG PRIORITY block: adds one "never copy their details" bullet.
#   3. RAGShortcut path: exposes the source pair via @rag_examples so the new
#      guard also covers Bella::QuickRephrase output.
#   4. guard_against_false_load_claim: chains the new guard after the
#      invented-balance link.
#   5. Adds RAG_LEAK_STOPWORDS + rag_example_leak_candidates +
#      rag_leak_allowed_text + guard_against_rag_example_leakage.
#   6. Adds sanitize_rag_example_text (prompt-side scrub).
#   7. build_rag_enhanced_prompt: examples are sanitized + wrapper wording says
#      TONE/FLOW only, never copy names/usernames/amounts.
#
# SAFETY: pure text replacement with unique anchors. Aborts (changing nothing)
# if any anchor is missing or ambiguous. Idempotent: re-running after a
# successful apply prints "already applied" and exits 0. Handles CRLF checkouts.
# ─────────────────────────────────────────────────────────────────────────────

# Optional ARGV[0] target override exists ONLY so the patch can be dry-run
# against a copy of the file; normal use is no arguments.
TARGET = ARGV[0] || 'app/services/ai/reply_service.rb'

abort "[change1] #{TARGET} not found — run from the repo root" unless File.exist?(TARGET)

original = File.read(TARGET, encoding: 'UTF-8')
crlf = original.include?("\r\n")
text = crlf ? original.gsub("\r\n", "\n") : original.dup

if text.include?('guard_against_rag_example_leakage')
  puts '[change1] already applied — nothing to do.'
  exit 0
end

# Each entry: [label, anchor, replacement]. Anchor must appear EXACTLY once.
EDITS = []

# ── 1. SYSTEM_PROMPT: stop "copy exactly" ────────────────────────────────────
EDITS << [
  'system-prompt-follow-exactly',
  '    - The training examples are from REAL conversations with REAL customers — follow their style and actions exactly',
  '    - The training examples are from REAL conversations with REAL customers — follow their style and actions, but the names, usernames, and dollar amounts in them belong to OTHER customers: NEVER repeat those. Use only THIS customer\'s details'
]

# ── 2. SYSTEM_PROMPT: RAG PRIORITY extra bullet ──────────────────────────────
EDITS << [
  'system-prompt-rag-priority-bullet',
  "    - If training examples show creating accounts, you create accounts\n    - Never contradict what the training data shows",
  "    - If training examples show creating accounts, you create accounts\n    - Never contradict what the training data shows\n    - Names, usernames, and dollar amounts inside training examples are OTHER customers' details — never copy them into your reply"
]

# ── 3. RAGShortcut: expose the source pair to the new guard ──────────────────
EDITS << [
  'rag-shortcut-expose-examples',
  '              rephrased = Bella::QuickRephrase.call(',
  "              # RAGLEAK: expose the source pair so guard_against_rag_example_leakage\n              # (chained inside guard_against_false_load_claim below) also covers the\n              # rephrased shortcut reply.\n              @rag_examples = [{ customer: top[:pair].customer_text.to_s, cashier: top[:pair].cashier_text.to_s }]\n              rephrased = Bella::QuickRephrase.call("
]

# ── 4. Chain the new guard inside guard_against_false_load_claim ─────────────
EDITS << [
  'guard-chain-link',
  "    reply_text = guard_against_invented_balance(reply_text)\n    return reply_text if reply_text.blank?\n\n    # bp5 P8 (red-team A): fold common Cyrillic/Greek homoglyphs to Latin",
  "    reply_text = guard_against_invented_balance(reply_text)\n    return reply_text if reply_text.blank?\n\n    # RAGLEAK: block names/usernames/$ amounts copied from RAG training examples\n    # into a live reply — they belong to OTHER customers, never this one.\n    reply_text = guard_against_rag_example_leakage(reply_text)\n    return reply_text if reply_text.blank?\n\n    # bp5 P8 (red-team A): fold common Cyrillic/Greek homoglyphs to Latin"
]

# ── 5. Stopwords constant + candidates/allowed/guard methods ─────────────────
# NOTE: <<- (not <<~) so the written indentation survives into the hot file.
NEW_GUARD_CODE = <<-'RUBY'

  # RAGLEAK — capitalized / username-ish tokens in RAG examples that are NOT
  # another customer's identity (game names, payment platforms, weekdays,
  # common texting words). Lowercase. Never treated as leak candidates.
  RAG_LEAK_STOPWORDS = Set.new(%w[
    bella cashapp cash venmo paypal chime zelle varo boltpay apple google visa mastercard
    juwa juwa2 game games vault vegas sweeps ultra panda milky way fire kirin
    master orion stars vblink mafia gameroom machine
    firekirin gamevault pandamaster milkyway orionstars vegassweeps ultrapanda
    mrallinone cashmachine facebook messenger
    monday tuesday wednesday thursday friday saturday sunday
    today tomorrow tonight morning night weekend
    just send sent what when where which your this that okay sure sorry once done
    thanks thank welcome please congrats good great nice cool love perfect
    loaded loading load cashout redeem bonus freeplay deposit account username
    password screenshot balance points play playing win winning withdraw minimum
    need give want make check wait ready money time name same best link
    hello there here have will from with then they their about gonna wanna lemme
    yeah alright right also should could would still after before
  ]).freeze

  # RAGLEAK — tokens mined from @rag_examples that could identify ANOTHER
  # customer: capitalized name-like words, username-shaped tokens
  # (letters+digits mixed), and $ amounts. Memoized (one reply per instance).
  def rag_example_leak_candidates
    @rag_example_leak_candidates ||= begin
      names = Set.new
      usernames = Set.new
      amounts = Set.new
      Array(@rag_examples).each do |ex|
        txt = "#{ex[:customer]} #{ex[:cashier]}"
        txt.scan(/\$\s*(\d[\d,]{0,8}(?:\.\d{1,2})?)/).flatten.each { |a| amounts << a.delete(',').to_f }
        txt.scan(/\b(\d[\d,]{0,8}(?:\.\d{1,2})?)\s*(?:dollars?|bucks)\b/i).flatten.each { |a| amounts << a.delete(',').to_f }
        txt.scan(/\b[a-zA-Z][a-zA-Z._-]*\d[a-zA-Z0-9._-]*\b/).each do |u|
          usernames << u.downcase if u.length >= 5 && !RAG_LEAK_STOPWORDS.include?(u.downcase)
        end
        txt.scan(/\b([A-Z][a-z]{3,})\b/).flatten.each do |w|
          names << w.downcase unless RAG_LEAK_STOPWORDS.include?(w.downcase)
        end
      end
      { names: names, usernames: usernames, amounts: amounts }
    end
  end

  # RAGLEAK — everything Bella IS allowed to echo: the live conversation, this
  # contact's own identity, and account config (payment handles, game names).
  # Lowercased blob for substring checks. Memoized; lookups are best-effort.
  def rag_leak_allowed_text
    @rag_leak_allowed_text ||= begin
      parts = Array(@conversation_history_for_llm).map { |m| (m['content'] || m[:content]).to_s }
      parts << @routing_last_incoming_raw_content.to_s
      begin
        cid = fetch_sender_contact_id
        contact = cid.present? ? Contact.find_by(id: cid, account_id: account_id) : nil
        if contact
          parts << contact.name.to_s
          parts.concat((contact.custom_attributes || {}).values.map(&:to_s))
        end
      rescue StandardError
        nil
      end
      begin
        acct = Account.find_by(id: account_id)
        if acct.respond_to?(:payment_handles)
          acct.payment_handles.to_a.each do |h|
            parts << h.try(:display_name).to_s << h.try(:display_handle).to_s
          end
        end
        AgentGame.where(account_id: account_id).includes(:game).each do |ag|
          parts << ag.game&.name.to_s << ag.game&.slug.to_s
        end
      rescue StandardError
        nil
      end
      begin
        # configured policy numbers are Bella's OWN numbers, never a leak:
        # bonus percents, cashout min/max, game-rule caps and freeplay amounts.
        parts.concat(configured_bonus_percents.map { |p| format('%g', p) })
        if (pc = policy_resolver&.cashout).is_a?(Hash)
          parts << format('%g', pc['min'].to_f) if pc['min']
          parts << format('%g', pc['max'].to_f) if pc['max']
        end
        GameRule.where(account_id: account_id).each do |gr|
          %i[cashout_max_amount freeplay_amount deposit_bonus_percentage deposit_bonus_min_amount].each do |attr|
            v = gr.try(attr)
            parts << format('%g', v.to_f) if v.present?
          end
        end
      rescue StandardError
        nil
      end
      parts.join(' ').downcase
    end
  end

  # RAGLEAK — post-generation net: a name/username/$ amount that traces to a
  # retrieved RAG example but NOT to this conversation (or account config)
  # never ships. Rewrites to a safe defer line. Fails open on any error.
  def guard_against_rag_example_leakage(reply_text)
    return reply_text if reply_text.to_s.strip.empty?
    return reply_text if @rag_examples.blank?

    cands = rag_example_leak_candidates
    return reply_text if cands[:names].empty? && cands[:usernames].empty? && cands[:amounts].empty?

    allowed = rag_leak_allowed_text
    scan = normalize_guard_text(reply_text).downcase
    leaked = []

    (cands[:names] | cands[:usernames]).each do |tok|
      next if tok.length < 4
      next if allowed.include?(tok)

      leaked << tok if scan.match?(/(?<![a-z0-9$@_.-])#{Regexp.escape(tok)}(?![a-z0-9_.-])/)
    end

    reply_amounts = scan.scan(/\$\s*(\d[\d,]{0,8}(?:\.\d{1,2})?)/).flatten.map { |a| a.delete(',').to_f }
    reply_amounts.concat(scan.scan(/\b(\d[\d,]{0,8}(?:\.\d{1,2})?)\s*(?:dollars?|bucks)\b/).flatten.map { |a| a.delete(',').to_f })
    if reply_amounts.any?
      allowed_amounts = allowed.scan(/\d[\d,]{0,8}(?:\.\d{1,2})?/).map { |a| a.delete(',').to_f } + customer_provided_numbers
      reply_amounts.each do |amt|
        next unless cands[:amounts].any? { |ex_amt| (ex_amt - amt).abs < 0.01 }
        next if allowed_amounts.any? { |a| (a - amt).abs < 0.01 }

        leaked << format('$%g', amt)
      end
    end
    return reply_text if leaked.empty?

    Rails.logger.warn("[ReplyService] BLOCKED_RAG_EXAMPLE_LEAK tokens=#{leaked.uniq.join(',')} reply=#{reply_text.inspect[0..120]}")
    add_conversation_labels!(%w[blocked-rag-example-leak]) rescue nil
    'one sec, lemme double-check that for you 🙏'
  rescue StandardError => e
    Rails.logger.warn("[ReplyService] rag leak guard failed: #{e.class}: #{e.message}")
    reply_text
  end
RUBY

EDITS << [
  'guard-methods-after-customer-provided-numbers',
  "    (nums + sums).uniq\n  rescue StandardError\n    []\n  end",
  "    (nums + sums).uniq\n  rescue StandardError\n    []\n  end\n#{NEW_GUARD_CODE.chomp}"
]

# ── 6. Prompt-side sanitizer ─────────────────────────────────────────────────
SANITIZER_CODE = <<-'RUBY'
  # RAGLEAK — neutralize identifying details in a RAG example BEFORE it enters
  # the prompt: $ amounts -> $X, "66 bucks" -> X bucks, username-shaped tokens
  # -> [username], capitalized person-name-like words -> [name]. Fails open.
  def sanitize_rag_example_text(text)
    t = text.to_s
    t = t.gsub(/\$\s*\d[\d,]{0,8}(?:\.\d{1,2})?/, '$X')
    t = t.gsub(/\b\d[\d,]{0,8}(?:\.\d{1,2})?(?=\s*(?:dollars?|bucks)\b)/i, 'X')
    t = t.gsub(/\b[a-zA-Z][a-zA-Z._-]*\d[a-zA-Z0-9._-]*\b/) do |m|
      m.length >= 5 && !RAG_LEAK_STOPWORDS.include?(m.downcase) ? '[username]' : m
    end
    t.gsub(/\b[A-Z][a-z]{3,}\b/) do |m|
      RAG_LEAK_STOPWORDS.include?(m.downcase) ? m : '[name]'
    end
  rescue StandardError
    text.to_s
  end

RUBY

EDITS << [
  'sanitizer-before-build-rag-enhanced-prompt',
  '  def build_rag_enhanced_prompt(base_prompt, rag_examples, reply_pref = nil)',
  "#{SANITIZER_CODE}  def build_rag_enhanced_prompt(base_prompt, rag_examples, reply_pref = nil)"
]

# ── 7. build_rag_enhanced_prompt: sanitize + reword the wrapper ──────────────
OLD_EXAMPLES_BLOCK = <<-'RUBY'.chomp
    examples_section = if rag_examples.present?
      examples_text = rag_examples.map do |ex|
        "Customer: #{ex[:customer]}\nCashier: #{ex[:cashier]}"
      end.join("\n---\n")

      "\nHere are examples of how real cashiers reply to similar messages:\n#{examples_text}\n\nNow reply to this customer in the SAME style as the examples above."
    else
      ""
    end
RUBY

NEW_EXAMPLES_BLOCK = <<-'RUBY'.chomp
    examples_section = if rag_examples.present?
      examples_text = rag_examples.map do |ex|
        "Customer: #{sanitize_rag_example_text(ex[:customer])}\nCashier: #{sanitize_rag_example_text(ex[:cashier])}"
      end.join("\n---\n")

      "\nHere are past chats showing TONE and FLOW only (names, usernames, and dollar amounts are replaced with placeholders):\n#{examples_text}\n\nMatch the tone, length, and flow of these examples — but NEVER copy names, usernames, or dollar amounts from examples. Those belong to OTHER customers. Use ONLY this customer's own details from the conversation above."
    else
      ""
    end
RUBY

EDITS << ['rag-enhanced-prompt-sanitized-block', OLD_EXAMPLES_BLOCK, NEW_EXAMPLES_BLOCK]

# ── apply ────────────────────────────────────────────────────────────────────
problems = EDITS.filter_map do |(label, anchor, _)|
  n = text.split(anchor, -1).size - 1
  next if n == 1

  "#{label}: anchor found #{n} times (need exactly 1)"
end
if problems.any?
  puts '[change1] ABORT — file drifted from the version this patch was written for:'
  problems.each { |p| puts "  - #{p}" }
  puts '[change1] NOTHING was changed. Re-generate the patch against the current file.'
  exit 1
end

EDITS.each do |(label, anchor, replacement)|
  text = text.sub(anchor, replacement)
  puts "[change1] applied: #{label}"
end

text = text.gsub("\n", "\r\n") if crlf
File.write(TARGET, text, encoding: 'UTF-8')
puts "[change1] DONE — #{EDITS.size}/7 edits applied to #{TARGET}"
puts '[change1] Now run:  ruby -c app/services/ai/reply_service.rb   (expect "Syntax OK")'
