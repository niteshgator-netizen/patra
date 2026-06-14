#!/usr/bin/env ruby
# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# bin/verify_channels_ui.rb — source of truth for "the Channels screen is done".
#
# Asserts gates F1..F9; exits NON-ZERO on the first failing gate, 0 only when all
# pass. A gate raising an unexpected error is treated as a hard FAIL.
#
# DEGRADED MODE (declared): no local DB (only Render prod is reachable), so the
# behavioral gates are proven by STATIC code-path analysis — no Rails boot, no DB.
#
# SHARED TREE: a concurrent build may touch other files; file-set gates scope to
# MY_FILES so this judge verifies the Channels-UI change set in isolation.
# ─────────────────────────────────────────────────────────────────────────────

require 'json'

ROOT = File.expand_path('..', __dir__)
Dir.chdir(ROOT)

ROLLBACK_HASH = '7e606e416c14ea77a9a487ed14e28f5f6fd1ceb7'

CHANNELS_CTRL  = 'app/controllers/api/v1/accounts/patra/channels_controller.rb'
IDENTITIES_CTRL = 'app/controllers/api/v1/accounts/patra/facebook_identities_controller.rb'
LIFECYCLE_SVC  = 'app/services/patra/channel_lifecycle_service.rb'
SCREEN_VUE     = 'app/javascript/dashboard/routes/dashboard/patra/PatraFacebookAccounts.vue'
CHANNELS_API   = 'app/javascript/dashboard/api/patraChannels.js'
FBCONNECT_API  = 'app/javascript/dashboard/api/patraFacebookConnect.js'
ROUTER_JS      = 'app/javascript/dashboard/routes/dashboard/dashboard.routes.js'

MY_FILES = [
  'bin/verify_channels_ui.rb',
  CHANNELS_CTRL, IDENTITIES_CTRL, SCREEN_VUE, CHANNELS_API, FBCONNECT_API, ROUTER_JS
].freeze

HOT_FILES = [
  'app/services/ai/reply_service.rb',
  'app/services/games/conversation_orchestrator.rb',
  'app/services/games/intent_detector.rb',
  'app/services/facebook/chatwoot_bridge_service.rb'
].freeze

VENDOR_RE = /zernio|chatwoot/i
HEX_RE    = /#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{4}|[0-9a-fA-F]{3})\b/
RGB_RE    = /rgba?\(/i
HSL_RE    = /hsla?\(/i
# Theme-fragile named CSS colors. `white` is intentionally EXCLUDED — it is the
# one theme-neutral keyword the screen uses (white text on a --patra / --red
# fill, legible in both themes), as are transparent/currentColor/inherit. The
# (?<![\w-]) / (?![\w-]) boundaries stop it from matching var names like
# var(--green) or --red.
NAMED_COLOR_RE = /(?<![\w-])(?:black|red|green|blue|gray|grey|silver|orange|yellow|navy|teal|aqua|fuchsia|maroon|olive|lime|purple|pink|brown|gold|cyan|magenta|crimson|coral|salmon|khaki|violet|indigo|beige|ivory)(?![\w-])/i

# ── plumbing ─────────────────────────────────────────────────────────────────
class GateFailure < StandardError
  attr_reader :gate
  def initialize(gate, msg)
    @gate = gate
    super(msg)
  end
end

def fail_gate(gate, msg) = raise(GateFailure.new(gate, msg))

DEGRADED = []
def degraded!(gate) = (DEGRADED << gate unless DEGRADED.include?(gate))

def git(args) = `git #{args}`.to_s
def read(path)
  fail_gate('F0', "expected file missing: #{path}") unless File.exist?(path)
  File.read(path)
end

def def_re(name) = /^\s*def\s+#{Regexp.escape(name)}(?![\w!?])/
def has_def?(src, name) = (src =~ def_re(name) ? true : false)

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

def each_json_value(node, &blk)
  case node
  when Hash  then node.each_value { |v| each_json_value(v, &blk) }
  when Array then node.each { |v| each_json_value(v, &blk) }
  else blk.call(node)
  end
end

# .vue section extractors
def vue_section(src, tag)
  src.scan(/<#{tag}[^>]*>(.*?)<\/#{tag}>/m).map(&:first).join("\n")
end

def vue_inline_styles(src)
  # static style="…"/style='…' and bound :style="…"/:style='…' attribute values
  src.scan(/(?::style|style)\s*=\s*(["'])(.*?)\1/m).map { |m| m[1] }.join("\n")
end

def full_diff
  tracked = git("diff --name-only #{ROLLBACK_HASH}").split(/\r?\n/)
  untracked = git('ls-files --others --exclude-standard').split(/\r?\n/)
  (tracked + untracked).map(&:strip).reject(&:empty?).uniq.sort
end

FULL_DIFF = full_diff
CHANGED = MY_FILES.select { |f| File.exist?(f) }
FOREIGN = (FULL_DIFF - MY_FILES).sort

# ── GATES ────────────────────────────────────────────────────────────────────
def f1_syntax
  missing = MY_FILES.reject { |f| File.exist?(f) }
  fail_gate('F1', "expected file(s) missing — an edit did not land: #{missing.join(', ')}") unless missing.empty?

  CHANGED.select { |f| f.end_with?('.rb') }.each do |f|
    out = IO.popen(['ruby', '-c', f], err: %i[child out], &:read)
    fail_gate('F1', "ruby -c failed for #{f}:\n#{out}") unless $?.success?
  end
  "PASS — ruby -c clean on every changed .rb (#{FOREIGN.size} foreign files excluded)"
end

def f2_status_truth
  svc = read(LIFECYCLE_SVC)
  fail_gate('F2', "lifecycle STATUS_KEY is not 'connection_status'") unless svc =~ /STATUS_KEY\s*=\s*'connection_status'/
  fail_gate('F2', "lifecycle STATUS_INACTIVE is not 'inactive'") unless svc =~ /STATUS_INACTIVE\s*=\s*'inactive'/

  ctrl = read(CHANNELS_CTRL)
  body = method_body(ctrl, 'channel_info')
  fail_gate('F2', 'channel_info not found in channels_controller') unless body
  fail_gate('F2', 'channel_info status does not consult the lifecycle flag (STATUS_KEY / connection_status)') unless body =~ /STATUS_KEY|connection_status/
  fail_gate('F2', 'channel_info does not surface an inactive status from the flag') unless body =~ /STATUS_INACTIVE|'inactive'/
  # The `status:` value must be conditioned on the inactive flag, not raw inbox_status only.
  fail_gate('F2', "channel_info `status:` is still the bare activity probe — must reflect 'inactive'") unless body =~ /status:\s*[^\n]*inactive/i

  degraded!('F2')
  'PASS (degraded/static) — channels#index status returns inactive when the lifecycle flag is set'
end

def f3_identity_shape
  ctrl = read(IDENTITIES_CTRL)
  # The per-inbox serialization (named helper or inline map) must include status + fb_page_id.
  inbox_region = method_body(ctrl, 'serialize_inbox') ||
                 (ctrl[/inboxes:\s*fi\.inboxes\.map.*?\}/m] || '')
  fail_gate('F3', 'could not locate the per-inbox serialization') if inbox_region.to_s.empty?
  fail_gate('F3', 'serialized inbox is missing :status') unless inbox_region =~ /status:/
  fail_gate('F3', 'serialized inbox is missing :fb_page_id') unless inbox_region =~ /fb_page_id:/
  degraded!('F3')
  'PASS (degraded/static) — facebook_identities inboxes each carry :status + :fb_page_id'
end

def f4_theme_safety
  src = read(SCREEN_VUE)
  styles = vue_section(src, 'style')
  inline = vue_inline_styles(src)
  blob = "#{styles}\n#{inline}"

  if (m = blob.match(HEX_RE))
    fail_gate('F4', "hardcoded hex color in the screen's styles: #{m[0]} (use var(--…) instead)")
  end
  if (m = blob.match(RGB_RE))
    fail_gate('F4', "hardcoded rgb()/rgba() color in the screen's styles: …#{blob[m.begin(0), 24]}… (use var(--…))")
  end
  if blob.match(HSL_RE)
    fail_gate('F4', "hardcoded hsl()/hsla() color in the screen's styles (use var(--…))")
  end
  if (m = blob.match(NAMED_COLOR_RE))
    fail_gate('F4', "theme-fragile named color '#{m[0]}' in the screen's styles (use var(--…); only `white` is allowed)")
  end
  # Positive proof it actually themes via variables.
  fail_gate('F4', 'screen styles use no var(--…) at all — would not theme dark/light') unless blob.include?('var(--')

  'PASS — screen styles/inline use var(--…) only; zero hex / rgb() / hsl() / theme-fragile named colors'
end

def f5_wiring
  # Whole-file checks (JS template literals contain `}`, so bounded body regexes
  # would misfire). The api files are small and single-purpose.
  api = read(CHANNELS_API)
  fail_gate('F5', 'patraChannels.js disconnect() not wired to /disconnect') unless api =~ /\bdisconnect\s*\(/ && api.include?('/disconnect')
  fail_gate('F5', 'patraChannels.js reconnect() not wired to /reconnect') unless api =~ /\breconnect\s*\(/ && api.include?('/reconnect')
  fail_gate('F5', 'patraChannels.js missing a destroy/delete method') unless api =~ /\b(?:destroy|deleteChannel|removeChannel)\s*\(/
  fail_gate('F5', 'channel delete does not use axios.delete') unless api =~ /axios\.delete/
  fail_gate('F5', 'channel delete does not send confirm: true') unless api =~ /confirm:\s*true/

  fb = read(FBCONNECT_API)
  fail_gate('F5', 'patraFacebookConnect.js syncPages() not wired to /sync_pages') unless fb =~ /\bsyncPages\s*\(/ && fb.include?('/sync_pages')
  fail_gate('F5', 'patraFacebookConnect.js fbConnect() not wired to /fb_connect') unless fb =~ /\bfbConnect\s*\(/ && fb.include?('/fb_connect')

  screen = read(SCREEN_VUE)
  %w[disconnect reconnect].each do |m|
    fail_gate('F5', "screen does not call #{m}") unless screen =~ /#{m}\s*\(/
  end
  fail_gate('F5', 'screen does not call a channel delete/destroy') unless screen =~ /\.(?:destroy|deleteChannel|removeChannel)\s*\(/
  fail_gate('F5', 'screen does not call syncPages') unless screen =~ /syncPages\s*\(/

  'PASS — disconnect / reconnect / delete(confirm) / sync_pages wired component→api→route'
end

def f6_controls
  tmpl = vue_section(read(SCREEN_VUE), 'template')
  fail_gate('F6', 'no Disconnect control in template') unless tmpl =~ /Disconnect/i
  fail_gate('F6', 'no Delete control in template') unless tmpl =~ /\bDelete\b/i
  fail_gate('F6', 'no Reconnect control in template') unless tmpl =~ /Reconnect/i
  fail_gate('F6', 'Reconnect is not conditionally shown only when inactive (needs v-if="isInactive(…)" gating the Reconnect control)') unless tmpl =~ /v-if="isInactive\([^"]*\)"[\s\S]{0,300}?Reconnect/i
  fail_gate('F6', 'no "Manage Pages" entry in template') unless tmpl =~ /Manage\s*Pages/i
  'PASS — Disconnect + Delete + Reconnect(when inactive) + Manage Pages all present'
end

def f7_white_label
  tmpl = vue_section(read(SCREEN_VUE), 'template')
  if (m = tmpl.match(VENDOR_RE))
    fail_gate('F7', "user-visible vendor name in screen template: #{m[0]}")
  end
  CHANGED.select { |f| f.end_with?('.json') && f.include?('i18n') }.each do |f|
    each_json_value(JSON.parse(File.read(f))) do |v|
      fail_gate('F7', "user-visible vendor name in #{f}: #{v.inspect}") if v.is_a?(String) && v =~ VENDOR_RE
    end
  end
  'PASS — zero user-visible Zernio/Chatwoot in the screen template + changed i18n values'
end

def f8_route
  router = read(ROUTER_JS)
  reachable = router =~ /path:\s*'patra\/channels'/ ||
              (router =~ /path:\s*'patra\/facebook-accounts'/ && router =~ /component:\s*PatraFacebookAccounts/)
  fail_gate('F8', 'Channels screen is not registered in the dashboard router (no patra/channels or patra/facebook-accounts route)') unless reachable
  fail_gate('F8', 'router does not import the screen component') unless router =~ /import\s+PatraFacebookAccounts/
  'PASS — Channels screen route is registered and reachable in the dashboard router'
end

def f9_safety
  hit = HOT_FILES & CHANGED
  fail_gate('F9', "HOT FILE(S) in the change set — forbidden: #{hit.join(', ')}") unless hit.empty?
  foreign_hot = HOT_FILES & FOREIGN
  warn "  ! F9 NOTE: a concurrent feature (not this change set) touched hot file(s): #{foreign_hot.join(', ')}" unless foreign_hot.empty?
  degraded!('F9')
  'PASS — no hot files in the change set; this script opens no DB and runs no app code'
end

# ── RUNNER ───────────────────────────────────────────────────────────────────
GATES = [
  ['F1  syntax',        method(:f1_syntax)],
  ['F2  status-truth',  method(:f2_status_truth)],
  ['F3  identity-shape', method(:f3_identity_shape)],
  ['F4  theme-safety',  method(:f4_theme_safety)],
  ['F5  wiring',        method(:f5_wiring)],
  ['F6  controls',      method(:f6_controls)],
  ['F7  white-label',   method(:f7_white_label)],
  ['F8  route',         method(:f8_route)],
  ['F9  safety',        method(:f9_safety)]
].freeze

puts '═════════════════════════════════════════════════════════════════════════'
puts ' PATRA · CHANNELS SCREEN — verify_channels_ui.rb'
puts " rollback=#{ROLLBACK_HASH[0, 10]}  screen_files=#{CHANGED.size}  foreign(excluded)=#{FOREIGN.size}"
puts ' MODE: no local DB (prod-only) → behavioral gates are static code-path proofs.'
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
puts '═════════════════════════════════════════════════════════════════════════'
exit 0
