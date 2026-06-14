#!/usr/bin/env ruby
# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# bin/verify_lifecycle.rb — the single source of truth for "the Channel
# Lifecycle Backend is done".
#
# Asserts gates G1..G13. Exits NON-ZERO on the FIRST failing gate with a precise
# message; exits 0 only when every gate passes. A gate that raises an UNEXPECTED
# error (not a deliberate failure) is treated as a hard FAIL, never an ambiguous
# crash.
#
# DEGRADED MODE (declared, never silent):
#   No local database is reachable, and the only Postgres this machine can reach
#   is Render PRODUCTION (via PATRA_DATABASE_URL). Per CLAUDE.md, booting Rails /
#   opening a DB transaction locally can touch prod and decrypt prod-only creds.
#   So the BEHAVIORAL gates are proven by STATIC code-path analysis of the real
#   source — not by live execution. Every degraded gate says so on its line.
#
# SHARED TREE: a separate agent is concurrently writing an unrelated feature
#   (backup-pages / team-roles) into the same checkout. File-set gates (G1/G10/
#   G11) are scoped to MY_FILES so this gate verifies the lifecycle feature in
#   isolation; the foreign files are reported but never gate this feature.
#
# Run from anywhere: `ruby bin/verify_lifecycle.rb`
# ─────────────────────────────────────────────────────────────────────────────

require 'json'

ROOT = File.expand_path('..', __dir__)
Dir.chdir(ROOT)

ROLLBACK_HASH = 'c819842f7f5728f151fa349c2beba28b6bcb50c8'

SERVICE_PATH             = 'app/services/patra/channel_lifecycle_service.rb'
WEBHOOK_PATH             = 'app/controllers/webhooks/zernio_controller.rb'
ZERNIO_PROVIDER_PATH     = 'app/services/messaging/zernio_provider.rb'
DIRECT_META_PATH         = 'app/services/messaging/direct_meta_provider.rb'
BASE_PROVIDER_PATH       = 'app/services/messaging/base_provider.rb'
CHANNELS_CONTROLLER_PATH = 'app/controllers/api/v1/accounts/patra/channels_controller.rb'
FB_CONNECT_PATH          = 'app/controllers/api/v1/accounts/patra/facebook_connect_controller.rb'
ROUTES_PATH              = 'config/routes.rb'

DEP_FILES = [BASE_PROVIDER_PATH, DIRECT_META_PATH].freeze

HOT_FILES = [
  'app/services/ai/reply_service.rb',
  'app/services/games/conversation_orchestrator.rb',
  'app/services/games/intent_detector.rb',
  'app/services/facebook/chatwoot_bridge_service.rb'
].freeze

VENDOR_RE = /zernio|chatwoot/i

# Record/bulk destructors a "keep data" method must never (transitively) reach.
# NB: the service uses Hash#except (not Hash#delete) precisely so /\.delete\b/
# below can stay broad without a false positive on token invalidation.
DESTRUCTIVE = [
  /\.destroy\b/, /\.destroy_all\b/, /\.destroy_by\b/,
  /\.delete\b/, /\.delete_all\b/, /\.delete_by\b/,
  /destroy_async/, /\bupdate_all\b/,
  /exec_delete/, /exec_update/, /connection\.execute/,
  /(?:public_)?send\(\s*['":](?:destroy|delete)/ # dynamic dispatch to a destroyer
].freeze

# ── failure + degradation plumbing ───────────────────────────────────────────
class GateFailure < StandardError
  attr_reader :gate
  def initialize(gate, msg)
    @gate = gate
    super(msg)
  end
end

def fail_gate(gate, msg)
  raise GateFailure.new(gate, msg)
end

DEGRADED = []
def degraded!(gate)
  DEGRADED << gate unless DEGRADED.include?(gate)
end

# ── helpers ──────────────────────────────────────────────────────────────────
def git(args)
  `git #{args}`.to_s
end

def read(path)
  fail_gate('G0', "expected file missing: #{path}") unless File.exist?(path)
  File.read(path)
end

# Match a method definition tolerant of bang/question names, never matching a
# longer name (status vs statuses; delete vs delete_all).
def def_re(name)
  /^\s*def\s+#{Regexp.escape(name)}(?![\w!?])/
end

def has_def?(src, name)
  src =~ def_re(name) ? true : false
end

# Extract a method body as text: from `def name` to the `end` at the SAME
# indentation. Inner block `end`s are more-indented, so they are skipped.
def method_body(src, name)
  lines = src.lines
  start = lines.index { |l| l =~ def_re(name) }
  return nil unless start

  indent = lines[start][/\A\s*/]
  out = [lines[start]]
  (start + 1).upto(lines.length - 1) do |i|
    out << lines[i]
    break if lines[i].rstrip == "#{indent}end"
  end
  out.join
end

# Bare (non-receiver) method-call identifiers in a body, keeping bang/question
# suffixes. Excludes `.foo` / `Foo::bar` / `@ivar` so we only follow same-object
# local helper calls.
def methods_called_in(body)
  body.scan(/(?<![\w.:@$])([a-z_]\w*[!?]?)/).flatten.uniq
end

# Transitive destructor scan: does `entry` — or any same-file local helper it
# calls (recursively) — contain a record/bulk destructor? Returns "a -> b -> /re/"
# trail or nil. This closes "destroy hidden one indirection away".
def scan_for_destructors(src, entry, patterns, seen = [])
  return nil if seen.include?(entry)

  seen << entry
  body = method_body(src, entry)
  return nil unless body

  patterns.each { |re| return "#{entry} -> /#{re.source}/" if body =~ re }

  methods_called_in(body).each do |m|
    next if m == entry || seen.include?(m)
    next unless src =~ def_re(m) # only recurse into methods defined in THIS file

    hit = scan_for_destructors(src, m, patterns, seen)
    return "#{entry} -> #{hit}" if hit
  end
  nil
end

def each_json_value(node, &blk)
  case node
  when Hash  then node.each_value { |v| each_json_value(v, &blk) }
  when Array then node.each { |v| each_json_value(v, &blk) }
  else blk.call(node)
  end
end

# ── change-set ───────────────────────────────────────────────────────────────
# The Channel Lifecycle change set — the explicit files THIS feature owns. The
# working tree is SHARED with a concurrent build, so file-set gates scope here.
MY_FILES = [
  SERVICE_PATH,
  'bin/verify_lifecycle.rb',
  ZERNIO_PROVIDER_PATH,
  WEBHOOK_PATH,
  CHANNELS_CONTROLLER_PATH,
  FB_CONNECT_PATH,
  ROUTES_PATH,
  'app/javascript/dashboard/i18n/locale/en/patra.json'
].freeze

def full_diff
  tracked = git("diff --name-only #{ROLLBACK_HASH}").split(/\r?\n/)
  untracked = git('ls-files --others --exclude-standard').split(/\r?\n/)
  (tracked + untracked).map(&:strip).reject(&:empty?).uniq.sort
end

FULL_DIFF = full_diff
CHANGED = MY_FILES.select { |f| File.exist?(f) }
FOREIGN = (FULL_DIFF - MY_FILES).sort

# ─────────────────────────────────────────────────────────────────────────────
# GATES
# ─────────────────────────────────────────────────────────────────────────────

def g1_syntax
  missing = MY_FILES.reject { |f| File.exist?(f) }
  fail_gate('G1', "expected lifecycle file(s) missing — an edit did not land: #{missing.join(', ')}") unless missing.empty?

  CHANGED.select { |f| f.end_with?('.rb') }.each do |f|
    out = IO.popen(['ruby', '-c', f], err: %i[child out], &:read)
    fail_gate('G1', "ruby -c failed for #{f}:\n#{out}") unless $?.success?
  end

  CHANGED.select { |f| f.end_with?('.json') }.each do |f|
    JSON.parse(File.read(f))
  rescue JSON::ParserError => e
    fail_gate('G1', "invalid JSON in #{f}: #{e.message}")
  end

  "PASS — ruby -c clean + JSON parses on all #{CHANGED.size} lifecycle files (#{FOREIGN.size} foreign files excluded)"
end

def g2_boot
  src = read(SERVICE_PATH)
  fail_gate('G2', 'service does not define module Patra') unless src =~ /module\s+Patra/
  fail_gate('G2', 'service does not define class ChannelLifecycleService') unless src =~ /class\s+ChannelLifecycleService/

  # Dependency providers the lifecycle hard-calls must also exist and parse.
  DEP_FILES.each do |dep|
    fail_gate('G2', "dependency missing: #{dep}") unless File.exist?(dep)
    out = IO.popen(['ruby', '-c', dep], err: %i[child out], &:read)
    fail_gate('G2', "ruby -c failed for dependency #{dep}:\n#{out}") unless $?.success?
  end

  degraded!('G2')
  'PASS (degraded/static) — cannot boot Rails locally (prod-only DB); proved via ruby -c on service + provider deps + class presence'
end

def g3_surface
  src = read(SERVICE_PATH)
  %w[disconnect! delete! reconnect!].each do |m|
    fail_gate('G3', "ChannelLifecycleService is missing def #{m}") unless has_def?(src, m)
  end
  'PASS — ChannelLifecycleService defines disconnect!, delete!, reconnect!'
end

def g4_keep_history
  src = read(SERVICE_PATH)

  # disconnect! and every state-flip it can reach must contain NO record destructor.
  %w[disconnect! mark_disconnected! reactivate!].each do |entry|
    next unless has_def?(src, entry)

    hit = scan_for_destructors(src, entry, DESTRUCTIVE)
    fail_gate('G4', "#{entry} (transitively) reaches a destructor: #{hit} — disconnect must KEEP data") if hit
  end

  mark = method_body(src, 'mark_disconnected!')
  fail_gate('G4', 'mark_disconnected! never sets STATUS_INACTIVE') unless mark =~ /STATUS_INACTIVE/
  dis = method_body(src, 'disconnect!')
  fail_gate('G4', 'disconnect! does not flip the inbox inactive (no mark_disconnected!)') unless dis =~ /mark_disconnected!/

  degraded!('G4')
  'PASS (degraded/static) — disconnect! transitively reaches NO destructor and flips status=inactive (keep-history)'
end

def g5_idempotent
  src = read(SERVICE_PATH)
  dis  = method_body(src, 'disconnect!')
  tear = method_body(src, 'teardown_upstream')
  mark = method_body(src, 'mark_disconnected!')

  fail_gate('G5', 'teardown_upstream is not rescued — an upstream error could raise out of disconnect!') unless tear && tear =~ /rescue\s+StandardError/
  fail_gate('G5', 'disconnect! raises in its own body (not safe to repeat)') if dis =~ /^\s*raise\b/
  # Real merge: the flip must READ existing attributes and WRITE the merged var
  # back — not replace additional_attributes with a fresh literal (which would
  # wipe fb_page_id / zernio_account_id and break repeat-safety).
  fail_gate('G5', 'mark_disconnected! does not source additional_attributes from existing channel state') unless mark =~ /\(channel\.additional_attributes\s*\|\|/
  fail_gate('G5', 'mark_disconnected! does not write the merged `attrs` back (possible wholesale replace)') unless mark =~ /update!\(additional_attributes:\s*attrs\b/

  # Key-preservation: invalidate ONLY tokens via the vetted constant — NEVER the
  # routing identifiers (fb_page_id / zernio_account_id) that keep the inbox
  # findable and make repeat-disconnect a safe no-op. Without this, a future edit
  # adding a routing key to the except list would silently lose the binding.
  fail_gate('G5', 'mark_disconnected! must invalidate tokens via except(*INVALIDATED_TOKEN_KEYS)') unless mark =~ /except\(\*INVALIDATED_TOKEN_KEYS\)/
  fail_gate('G5', 'INVALIDATED_TOKEN_KEYS must be exactly the two token keys') unless src =~ /INVALIDATED_TOKEN_KEYS\s*=\s*%w\[fb_page_access_token fb_user_long_lived_token\]/
  %w[fb_page_id zernio_account_id].each do |k|
    fail_gate('G5', "INVALIDATED_TOKEN_KEYS must NOT include routing key '#{k}' (would wipe the inbox binding)") if src =~ /INVALIDATED_TOKEN_KEYS\s*=\s*%w\[[^\]]*#{k}/
  end

  degraded!('G5')
  'PASS (degraded/static) — upstream rescued; flip reads+merges existing attrs; no raise in disconnect! → repeat-safe'
end

def g6_delete_confirm
  src = read(SERVICE_PATH)
  body = method_body(src, 'delete!')
  fail_gate('G6', 'could not extract delete! body') unless body

  destroy_at = (body =~ /\.destroy!?\b/)
  guard_at   = (body =~ /unless\s+confirm\b/)
  fail_gate('G6', 'delete! never destroys, so confirm:true could not delete') unless destroy_at
  fail_gate('G6', 'delete! has no `unless confirm` guard') unless guard_at
  fail_gate('G6', 'delete! does not raise ConfirmationRequired when unconfirmed') unless body =~ /ConfirmationRequired/
  fail_gate('G6', 'delete! destroys BEFORE checking confirm') unless guard_at < destroy_at

  degraded!('G6')
  'PASS (degraded/static) — delete! raises ConfirmationRequired before any destroy; destroys only under confirm'
end

def g7_webhook
  src = read(WEBHOOK_PATH)
  fail_gate('G7', "no `when 'account.disconnected'` branch in zernio_controller") unless src =~ /when\s+'account\.disconnected'/
  body = method_body(src, 'handle_account_disconnected')
  fail_gate('G7', 'handle_account_disconnected is not defined') unless body
  fail_gate('G7', 'account.disconnected handler does not flip inactive (no mark_disconnected!)') unless body =~ /mark_disconnected!/

  hit = scan_for_destructors(src, 'handle_account_disconnected', DESTRUCTIVE)
  fail_gate('G7', "account.disconnected handler (transitively) reaches a destructor: #{hit} — it must keep the inbox") if hit

  degraded!('G7')
  'PASS (degraded/static) — account.disconnected flips inactive via mark_disconnected!; transitively reaches no destructor'
end

def g8_zernio_endpoint
  src = read(ZERNIO_PROVIDER_PATH)
  body = method_body(src, 'disconnect!')
  fail_gate('G8', 'could not extract ZernioProvider#disconnect!') unless body
  # Assert the actual verb+path shape, not merely substring presence.
  fail_gate('G8', 'ZernioProvider#disconnect! does not issue HTTParty.delete to …/accounts/{id}') unless body =~ %r{HTTParty\.delete\(\s*["'][^"']*/accounts/\#\{zernio_account_id\}}
  fail_gate('G8', 'ZernioProvider still references the stale /connections/ path') if src.include?('/connections/')
  'PASS — ZernioProvider#disconnect! issues HTTParty.delete to /v1/accounts/{id}; stale /connections/ path is gone'
end

def g8b_directmeta_teardown
  src = read(DIRECT_META_PATH)
  body = method_body(src, 'disconnect!')
  fail_gate('G8b', 'could not extract DirectMetaProvider#disconnect!') unless body
  fail_gate('G8b', 'DirectMeta disconnect! does not issue HTTParty.delete') unless body =~ /HTTParty\.delete/
  fail_gate('G8b', 'DirectMeta disconnect! does not unsubscribe the page webhook (/subscribed_apps)') unless body.include?('/subscribed_apps')
  'PASS — DirectMetaProvider#disconnect! unsubscribes the page webhook via Graph DELETE /{page}/subscribed_apps'
end

def g9_routes
  routes = read(ROUTES_PATH)
  lines = routes.lines
  patra_start = lines.index { |l| l =~ /namespace :patra do/ }
  fail_gate('G9', 'namespace :patra not found in routes.rb') unless patra_start
  sentinel = lines[(patra_start + 1)..].index { |l| l =~ /resources :webhooks/ }
  patra_end = sentinel ? patra_start + 1 + sentinel : lines.length

  {
    'post :disconnect'                       => /post\s+:disconnect/,
    'post :reconnect'                        => /post\s+:reconnect/,
    'channels delete (only: [..,:destroy])'  => /resources :channels,\s*only:\s*\[:index,\s*:destroy\]/,
    "post 'sync_pages'"                      => %r{post 'sync_pages', to: 'facebook_connect#sync_pages'}
  }.each do |label, re|
    idx = lines.index { |l| l !~ /\A\s*#/ && l =~ re } # ignore commented-out routes
    fail_gate('G9', "route not found (uncommented) in routes.rb: #{label}") unless idx
    fail_gate('G9', "route '#{label}' is OUTSIDE namespace :patra (line #{idx}, block #{patra_start}..#{patra_end})") unless idx > patra_start && idx < patra_end
  end

  cc = read(CHANNELS_CONTROLLER_PATH)
  %w[disconnect reconnect destroy].each do |a|
    fail_gate('G9', "ChannelsController is missing ##{a}") unless has_def?(cc, a)
  end
  fc = read(FB_CONNECT_PATH)
  fail_gate('G9', 'FacebookConnectController is missing #sync_pages') unless has_def?(fc, 'sync_pages')

  degraded!('G9')
  'PASS (degraded/static) — disconnect/reconnect/destroy(delete)/sync_pages routes are INSIDE namespace :patra + backing actions exist'
end

def g10_whitelabel
  json_changed = CHANGED.select { |f| f.end_with?('.json') && f.include?('i18n') }
  json_changed.each do |f|
    each_json_value(JSON.parse(File.read(f))) do |v|
      fail_gate('G10', "user-visible vendor name in #{f} VALUE: #{v.inspect}") if v.is_a?(String) && v =~ VENDOR_RE
    end
  end

  # Frontend files in scope: scan FULL source (not just <template>) for vendor
  # strings, allowing known internal identifiers. This change set ships none,
  # but the gate is capable of catching a leak if one is ever added.
  fe_changed = CHANGED.select { |f| f =~ /\.(vue|js|ts)\z/ }
  fe_changed.each do |f|
    File.read(f).scan(/["'`]([^"'`\n]*?(?:zernio|chatwoot)[^"'`\n]*?)["'`]/i) do |cap|
      s = cap[0]
      next if s =~ /\A\s*(zernio|direct_meta)\s*\z/i           # bare provider enum value
      next if s =~ /chatwootConfig|chatwootSettings|@chatwoot|\$chatwoot/i # internal ids

      fail_gate('G10', "possible user-visible vendor string in #{f}: #{s.inspect}")
    end
  end

  "PASS — 0 user-visible Zernio/Chatwoot in #{json_changed.size} i18n value-set(s) + #{fe_changed.size} frontend file(s)"
end

def g11_no_hot_files
  hit = HOT_FILES & CHANGED
  fail_gate('G11', "HOT FILE(S) in the lifecycle change set — forbidden: #{hit.join(', ')}") unless hit.empty?
  foreign_hot = HOT_FILES & FOREIGN
  warn "  ! G11 NOTE: a CONCURRENT feature (not this change set) touched hot file(s): #{foreign_hot.join(', ')}" unless foreign_hot.empty?
  'PASS — none of the 4 hot files are in the lifecycle change set'
end

def g12_no_real_data
  degraded!('G12')
  'PASS (degraded/static) — this script opens no DB connection and runs no app code; no real record could be touched'
end

def g13_manageability
  src = read(SERVICE_PATH)
  fail_gate('G13', 'service does not define patra_managed?') unless has_def?(src, 'patra_managed?')
  dis = method_body(src, 'disconnect!')
  fail_gate('G13', 'disconnect! does not guard on patra_managed? — a native/default direct_meta inbox would be flipped') unless dis =~ /patra_managed\?/

  cc = read(CHANNELS_CONTROLLER_PATH)
  %w[disconnect reconnect].each do |a|
    b = method_body(cc, a)
    fail_gate('G13', "ChannelsController##{a} does not reject non-managed inboxes (patra_managed?)") unless b && b =~ /patra_managed\?/
  end

  degraded!('G13')
  'PASS (degraded/static) — native/default-direct_meta inboxes are guarded out of disconnect & reconnect'
end

# ─────────────────────────────────────────────────────────────────────────────
# RUNNER
# ─────────────────────────────────────────────────────────────────────────────
GATES = [
  ['G1  syntax',          method(:g1_syntax)],
  ['G2  boot',            method(:g2_boot)],
  ['G3  surface',         method(:g3_surface)],
  ['G4  keep-history',    method(:g4_keep_history)],
  ['G5  idempotency',     method(:g5_idempotent)],
  ['G6  delete-confirm',  method(:g6_delete_confirm)],
  ['G7  webhook',         method(:g7_webhook)],
  ['G8  zernio-endpoint', method(:g8_zernio_endpoint)],
  ['G8b directmeta-down', method(:g8b_directmeta_teardown)],
  ['G9  routes',          method(:g9_routes)],
  ['G10 white-label',     method(:g10_whitelabel)],
  ['G11 no-hot-files',    method(:g11_no_hot_files)],
  ['G12 no-real-data',    method(:g12_no_real_data)],
  ['G13 manageability',   method(:g13_manageability)]
].freeze

puts '═════════════════════════════════════════════════════════════════════════'
puts ' PATRA · CHANNEL LIFECYCLE — verify_lifecycle.rb'
puts " rollback=#{ROLLBACK_HASH[0, 10]}  lifecycle_files=#{CHANGED.size}  foreign(concurrent build, excluded)=#{FOREIGN.size}"
puts ' MODE: no local DB reachable (prod-only) → behavioral gates proven by static'
puts '       code-path analysis. Degraded gates are labelled (degraded/static).'
puts "       SHARED TREE: #{FOREIGN.size} file(s) from a concurrent build are excluded from scope." unless FOREIGN.empty?
puts '═════════════════════════════════════════════════════════════════════════'

begin
  GATES.each do |label, m|
    result =
      begin
        m.call
      rescue GateFailure
        raise
      rescue StandardError => e
        fail_gate(label.split.first, "gate raised an UNEXPECTED error (treated as FAIL): #{e.class}: #{e.message}\n    #{e.backtrace.first(3).join("\n    ")}")
      end
    puts "  ✓ #{label.ljust(20)} #{result}"
  end
rescue GateFailure => e
  warn ''
  warn "  ✗ FAIL #{e.gate}: #{e.message}"
  warn ''
  warn "  Stopped at the first failing gate. Fix #{e.gate}, then re-run."
  exit 1
end

puts '─────────────────────────────────────────────────────────────────────────'
puts "  ALL #{GATES.size} GATES PASS.  degraded(static): #{DEGRADED.sort.join(', ')}"
puts '  (degraded gates are static code-path proofs — no Rails boot, no DB, by design)'
puts '═════════════════════════════════════════════════════════════════════════'
exit 0
