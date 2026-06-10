# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# PATRA INTENT GOLDEN SUITE (H1) — drives the REAL Games::IntentDetector.detect
# over every pattern family x canonical / slang / misspelled / adversarial.
# Read-only, zero network, zero DB writes.
#
#   RUN (Render Shell):  bundle exec rails runner script/patra_intent_suite.rb
#   (also runnable locally via tmp/self_tests/h1_intent_suite_local.rb shim)
#
# Each case: [text, expected] where expected is nil or {intent:, ...optional
# keys to assert (amount, platform, game_slugs)}. Expected values encode
# VERIFIED current behavior except where marked FIXED(H1-greeting).
# ─────────────────────────────────────────────────────────────────────────────

PATRA_INTENT_CASES = [
  # ── greeting ──
  ['hey',                       { intent: :greeting }],
  ['Hi',                        { intent: :greeting }],
  ['yo',                        { intent: :greeting }],
  ['wassup',                    { intent: :greeting }],
  ['hola amigo',                { intent: :greeting }],
  # adversarial: greeting prefix must NOT steal money intents (H1-greeting fix)
  ['hey can i load 20',         { intent: :load, amount: 20.0 }],
  ['hello i wanna cash out',    { intent: :cashout }],

  # ── status_check ──
  ['any update',                { intent: :status_check }],
  ['did it go through',         { intent: :status_check }],
  ['still waiting',             { intent: :status_check }],
  ['whats the status',          { intent: :status_check }],
  ['can you check on it',       { intent: :status_check }],
  # adversarial: status question about a load is NOT a new load
  ['any update on my load?',    { intent: :status_check }],

  # ── cashout_rules (asking ABOUT limits, not cashing out) ──
  ['cash out rules',            { intent: :cashout_rules }],
  ['minimum cashout',           { intent: :cashout_rules }],
  ['how much can i cash out',   { intent: :cashout_rules }],
  ['withdrawal limit',          { intent: :cashout_rules }],
  ['min to redeem',             { intent: :cashout_rules }],

  # ── cashout ──
  ['cash out 50',               { intent: :cashout, amount: 50.0 }],
  ['cashout 100',               { intent: :cashout, amount: 100.0 }],
  ['redeem 75',                 { intent: :cashout, amount: 75.0 }],
  ['withdraw $40',              { intent: :cashout, amount: 40.0 }],
  ['i wanna cash out',          { intent: :cashout }],
  ['I want to cashout',         { intent: :cashout }],
  ['payout 60',                 { intent: :cashout, amount: 60.0 }],
  ['cash out 25.50',            { intent: :cashout, amount: 25.5 }],

  # ── freeplay / bonus ──
  ['any freeplay',              { intent: :load_freeplay }],
  ['fp please',                 { intent: :load_freeplay }],
  ['free play?',                { intent: :load_freeplay }],
  ['can i get my fp',           { intent: :load_freeplay }],
  ['bonus?',                    { intent: :load_bonus }],
  ['any promo today',           { intent: :load_bonus }],
  ['signup promotion',          { intent: :load_bonus }],
  ['deposit bonus',             { intent: :load_bonus }],

  # ── balance REPORT (number present — must not be stolen by load) ──
  ['i got 22 on there',         { intent: :balance_check }],
  ['only 5 dollars left in juwa', { intent: :balance_check }],
  ['still have 30',             { intent: :balance_check }],
  ['2 dollars on gv',           { intent: :balance_check }],

  # ── balance QUESTION ──
  ['whats my balance',          { intent: :balance_check }],
  ['how much do i have',        { intent: :balance_check }],
  ['check my balance',          { intent: :balance_check }],
  ['0 balance',                 { intent: :balance_check }],
  ['says i got a zero',         { intent: :balance_check }],

  # ── load ──
  ['load 20',                   { intent: :load, amount: 20.0 }],
  ['load me $50',               { intent: :load, amount: 50.0 }],
  ['add 25',                    { intent: :load, amount: 25.0 }],
  ['recharge 10',               { intent: :load, amount: 10.0 }],
  ['top up 30',                 { intent: :load, amount: 30.0 }],
  ['deposit 40',                { intent: :load, amount: 40.0 }],
  ['put 5 on gv',               { intent: :load, amount: 5.0 }],
  ['load 22 on juwa',           { intent: :load, amount: 22.0 }],
  ['$20 on juwa',               { intent: :load, amount: 20.0 }],
  ['20$ on juwa',               { intent: :load, amount: 20.0 }],
  ['load please on gameroom',   { intent: :load }],
  ['load it',                   { intent: :load }],
  ['load twenty',               { intent: :load }], # word amounts unsupported -> amount nil (documented gap)
  # adversarial: "load" inside "download" must NOT fire load
  ['where do i download juwa',  { intent: :request_download_link }],

  # ── account creation ──
  ['create me an account',      { intent: :request_account_creation }],
  ['sign me up',                { intent: :request_account_creation }],
  ['never played before',       { intent: :request_account_creation }],
  ['i need a juwa account',     { intent: :request_account_creation }],
  ['hook me up',                { intent: :request_account_creation }],
  ['make me an account on juwa and gv', { intent: :request_multi_account_creation }],
  ['set me up an account on all games', { intent: :request_multi_account_creation }],

  # ── reset password ──
  ['reset my password',         { intent: :reset_password }],
  ['forgot my pass',            { intent: :reset_password }],
  ['cant login',                { intent: :reset_password }],
  ['my password isnt working',  { intent: :reset_password }],

  # ── payment method PICK ──
  ['cashapp',                   { intent: :payment_method_chosen, platform: 'cashapp' }],
  ['cash app',                  { intent: :payment_method_chosen, platform: 'cashapp' }],
  ["i'll use paypal",           { intent: :payment_method_chosen, platform: 'paypal' }],
  ['lets do venmo',             { intent: :payment_method_chosen, platform: 'venmo' }],
  ['send me your cashapp tag',  { intent: :payment_method_chosen, platform: 'cashapp' }],
  ['PayPal?',                   { intent: :payment_method_chosen, platform: 'paypal' }],
  ['i got chime',               { intent: :payment_method_chosen, platform: 'chime' }],

  # ── pick GUARDS (questions / negations / standdowns are NOT picks) ──
  ["i don't want to use cashapp", nil],
  ['you only have cash app?',   nil],
  ['who do i send the request to on cashapp', nil],
  # game named "cash machine" is a GAME, not a payment pick
  ['cash machine',              nil],

  # ── payment method QUESTION ──
  ['what payment methods do you have', { intent: :payment_method_question }],
  ['how do i pay',              { intent: :payment_method_question }],
  ['what do you accept',        { intent: :payment_method_question }],
  ['how can i send',            { intent: :payment_method_question }],

  # ── payment sent confirmation ──
  ['i sent the money',          { intent: :payment_sent_confirmation }],
  ['just paid you',             { intent: :payment_sent_confirmation }],
  ['sent it',                   { intent: :payment_sent_confirmation }],
  ['payment sent',              { intent: :payment_sent_confirmation }],

  # ── complaint ──
  ['wtf',                       { intent: :complaint_angry }],
  ['this is a scam',            { intent: :complaint_angry }],
  ['im so pissed',              { intent: :complaint_angry }],
  ['worst service ever',        { intent: :complaint_angry }],

  # ── tech issue ──
  ['game not working',          { intent: :tech_issue }],
  ['cant get into the app',     { intent: :tech_issue }],
  ['app is down',               { intent: :tech_issue }],
  ['it keeps crashing',         { intent: :tech_issue }],

  # ── transfer ──
  ['transfer my points to juwa', { intent: :transfer_between_games }],
  ['move it from gv to juwa',   { intent: :transfer_between_games }],
  ['switch my balance to orion', { intent: :transfer_between_games }],
  ['port my credits to vegas',  { intent: :transfer_between_games }],

  # ── whats hitting (before list_platforms!) ──
  ['whats hitting',             { intent: :whats_hitting }],
  ['what games are hitting',    { intent: :whats_hitting }],
  ['any good games hitting',    { intent: :whats_hitting }],
  ['whats good right now',      { intent: :whats_hitting }],

  # ── referral ──
  ['i referred a friend',       { intent: :referral }],
  ['use my referral code',      { intent: :referral }],
  # NOTE current behavior: BONUS_PATTERNS branch runs before REFERRAL, so
  # 'referral bonus' routes to load_bonus. Report-only candidate; reordering
  # hot-file branches is not a zero-regression-safe change.
  ['referral bonus',            { intent: :load_bonus }],
  ['she used my name',          { intent: :referral }],

  # ── links ──
  ['download',                  { intent: :request_download_link }],
  ['send me the apk',           { intent: :request_download_link }],
  ['how to install',            { intent: :request_download_link }],
  ['app link',                  { intent: :request_app_link }],
  ['get the app',               { intent: :request_app_link }],
  ['link to play',              { intent: :request_game_link }],
  ['where can i play',          { intent: :request_game_link }],
  ['play online',               { intent: :request_game_link }],

  # ── list platforms ──
  ['what games you got',        { intent: :list_platforms }],
  ['which games do you have',   { intent: :list_platforms }],
  ['list games',                { intent: :list_platforms }],
  ['what platforms',            { intent: :list_platforms }],

  # ── username provided ──
  ['username: bigwinner99',     { intent: :username_provided }],
  ['my username is john_123',   { intent: :username_provided }],
  ['user bigdog22',             { intent: :username_provided }],
  ['im slickrick7 on juwa',     { intent: :username_provided }],

  # ── cashout with extras (amount + tip + reload + method) ──
  ['cash out 100 and tip 10 and reload 20 my cashapp is $johnny5',
   { intent: :cashout, amount: 100.0, tip_amount: 10.0, reload_amount: 20.0 }],

  # ── no-intent fallthroughs (LLM brain handles) ──
  ['$20', nil],
  ['twenty on juwa', nil],
  ['i sent the screenshot', nil],
  ['good morning everyone hope yall are doing great today', nil]
].freeze

def run_patra_intent_suite(cases = PATRA_INTENT_CASES)
  pass = 0
  fails = []
  puts '=' * 90
  puts format('%-44s %-28s %s', 'TEXT', 'EXPECTED', 'ACTUAL')
  puts '-' * 90
  cases.each do |(text, expected)|
    actual = begin
      Games::IntentDetector.detect(text)
    rescue StandardError => e
      { error: "#{e.class}: #{e.message}" }
    end

    ok =
      if expected.nil?
        actual.nil?
      elsif actual.is_a?(Hash)
        expected.all? do |k, v|
          k == :intent ? actual[:intent] == v : actual[k] == v
        end
      else
        false
      end

    exp_s = expected.nil? ? 'nil' : expected.map { |k, v| "#{k}=#{v}" }.join(' ')
    act_s = actual.nil? ? 'nil' : (actual[:error] || actual.slice(:intent, :amount, :platform, :tip_amount, :reload_amount).compact.map { |k, v| "#{k}=#{v}" }.join(' '))
    if ok
      pass += 1
    else
      fails << [text, exp_s, act_s]
    end
    puts format('%-44s %-28s %s %s', text[0, 43], exp_s[0, 27], act_s[0, 40], ok ? '' : '   <<< FAIL')
  end
  puts '-' * 90
  puts "INTENT SUITE: #{pass}/#{cases.size} pass, #{fails.size} fail"
  fails.each { |(t, e, a)| puts "  FAIL #{t.inspect}: expected #{e} got #{a}" }
  puts '=' * 90
  fails.empty?
end

exit(run_patra_intent_suite ? 0 : 1) unless ENV['PATRA_INTENT_SUITE_NO_AUTORUN']
