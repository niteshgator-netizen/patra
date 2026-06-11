# frozen_string_literal: true

# MEGA2 P7 - report-only DB integrity probe. ZERO writes - every statement is
# a SELECT against catalogs. Run on Render:
#   bundle exec rails runner script/patra_db_integrity_check.rb
#
# Checks: hairtriggers (conversations, campaigns), the unique indexes the app
# logic relies on, NOT NULL columns the code assumes, serial-PK sequence
# health (last_value >= max(id) - a behind-sequence means inserts will start
# colliding), and presence of key foreign keys.

conn = ActiveRecord::Base.connection
results = []
check = lambda do |section, name, ok, detail = nil|
  results << [section, name, ok, detail]
  puts format('[%-9s] %-70s %s%s', section, name, ok ? 'PASS' : 'FAIL', detail ? " (#{detail})" : '')
end

# ---------- 1. hairtriggers ----------
%w[conversations campaigns].each do |table|
  rows = conn.select_values(<<~SQL)
    SELECT tgname FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE c.relname = '#{table}' AND NOT t.tgisinternal
  SQL
  check.call('TRIGGER', "#{table} hairtrigger present", rows.any?, rows.join(','))
end

# per-account display_id sequences behind the triggers
%w[conv_dpid_seq camp_dpid_seq].each do |prefix|
  count = conn.select_value(
    "SELECT COUNT(*) FROM pg_class WHERE relkind = 'S' AND relname LIKE '#{prefix}_%'"
  ).to_i
  check.call('TRIGGER', "#{prefix}_<account_id> sequences exist", count.positive?, "#{count} found")
end

# ---------- 2. unique indexes the code relies on ----------
EXPECTED_UNIQUE = [
  ['game_actions',      %w[account_id order_id]],   # F12 / appr_<id> idempotency
  ['conversations',     %w[account_id display_id]],
  ['conversations',     %w[uuid]],
  ['account_users',     %w[account_id user_id]],
  ['access_tokens',     %w[token]]
].freeze

EXPECTED_UNIQUE.each do |(table, cols)|
  rows = conn.select_rows(<<~SQL)
    SELECT i.relname, ARRAY_TO_STRING(ARRAY(
      SELECT a.attname FROM unnest(ix.indkey) WITH ORDINALITY AS k(attnum, ord)
      JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
      ORDER BY k.ord), ',')
    FROM pg_index ix
    JOIN pg_class t ON t.oid = ix.indrelid
    JOIN pg_class i ON i.oid = ix.indexrelid
    WHERE t.relname = '#{table}' AND ix.indisunique
  SQL
  found = rows.any? { |(_, collist)| collist == cols.join(',') }
  check.call('UNIQUE', "#{table}(#{cols.join(', ')}) unique index", found)
end

# ---------- 3. NOT NULL columns the code assumes ----------
EXPECTED_NOT_NULL = {
  'game_actions'      => %w[account_id agent_game_id action_type order_id status],
  'approval_requests' => %w[account_id requesting_user_id action_type status],
  'referrals'         => %w[account_id referrer_contact_id]
}.freeze

EXPECTED_NOT_NULL.each do |table, cols|
  nn = conn.select_values(<<~SQL)
    SELECT column_name FROM information_schema.columns
    WHERE table_name = '#{table}' AND is_nullable = 'NO'
  SQL
  cols.each do |col|
    check.call('NOT NULL', "#{table}.#{col}", nn.include?(col))
  end
end

# ---------- 4. serial-PK sequence health ----------
serial_tables = conn.select_rows(<<~SQL)
  SELECT c.table_name, pg_get_serial_sequence(c.table_name, 'id')
  FROM information_schema.columns c
  JOIN information_schema.tables t
    ON t.table_name = c.table_name AND t.table_schema = 'public' AND t.table_type = 'BASE TABLE'
  WHERE c.table_schema = 'public' AND c.column_name = 'id'
    AND c.column_default LIKE 'nextval%'
  ORDER BY c.table_name
SQL

behind = []
serial_tables.each do |(table, seq)|
  next if seq.blank?

  begin
    last_value, called = conn.select_rows("SELECT last_value, is_called FROM #{seq}").first
    max_id = conn.select_value("SELECT MAX(id) FROM #{conn.quote_table_name(table)}").to_i
    effective = called ? last_value.to_i : last_value.to_i - 1
    ok = effective >= max_id
    behind << table unless ok
    check.call('SEQUENCE', "#{table} seq last_value(#{effective}) >= max(id)(#{max_id})", ok,
               ok ? nil : 'BEHIND-SEQUENCE! next insert may collide')
  rescue StandardError => e
    check.call('SEQUENCE', "#{table} sequence readable", false, "#{e.class}: #{e.message[0, 80]}")
  end
end

# ---------- 5. key foreign keys ----------
EXPECTED_FKS = [
  %w[referrals accounts],
  %w[referrals contacts],
  %w[approval_requests accounts],
  %w[approval_requests users]
].freeze

fk_rows = conn.select_rows(<<~SQL)
  SELECT tc.table_name, ccu.table_name AS foreign_table
  FROM information_schema.table_constraints tc
  JOIN information_schema.constraint_column_usage ccu
    ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
  WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = 'public'
SQL

EXPECTED_FKS.each do |(table, foreign)|
  found = fk_rows.any? { |(t, f)| t == table && f == foreign }
  check.call('FK', "#{table} -> #{foreign}", found)
end

# ---------- exit summary ----------
puts "\n==== SUMMARY ===="
results.group_by(&:first).each do |section, rows|
  failed = rows.count { |(_, _, ok)| !ok }
  puts format('%-9s %d/%d passed%s', section, rows.size - failed, rows.size,
              failed.positive? ? " - #{failed} FAILED" : '')
end
puts "behind-sequence tables: #{behind.any? ? behind.join(', ') : 'none'}"
total_failed = results.count { |(_, _, ok)| !ok }
puts total_failed.zero? ? 'ALL CHECKS PASSED' : "#{total_failed} CHECK(S) FAILED"
