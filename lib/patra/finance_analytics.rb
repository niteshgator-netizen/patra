# frozen_string_literal: true

module Patra
  # Platform-wide money + risk rollups for the operator console (ADM1/ADM2).
  #
  # Sources (mirrors the per-account definitions in
  # app/services/owner_stats/aggregator.rb — READ-ONLY, that service is not
  # edited):
  #   - deposits/cashouts: contact.custom_attributes['patra_finance_logs']
  #     entries shaped { kind: deposit|cashout, amount:, logged_at: ISO8601 }.
  #     jsonb arrays can't be aggregated in pure SQL per-account, so contacts
  #     are scanned in batches of BATCH_SIZE via find_each (logged approach).
  #   - by-game money: GameAction rows (status=success, action_type
  #     load/cashout) — pure SQL group, zero N+1.
  #   - risk: a contact is "flagged" when any finance entry carries a
  #     non-empty flag_reason or kind == 'flagged' (the markers the AI
  #     pipeline writes for suspect payments). No other risk model exists in
  #     the repo (verified by grep, 2026-06-10).
  #
  # Malformed entries (non-hash, or deposit/cashout rows with unparseable
  # amount/time) are SKIPPED and COUNTED, never raised on.
  class FinanceAnalytics
    FINANCE_LOG_KEY = 'patra_finance_logs'
    BATCH_SIZE = 500
    MONEY_KINDS = %w[deposit cashout].freeze
    TOP_ACCOUNTS = 10

    def initialize(range:, account_id: nil)
      @range = range
      @account_id = account_id
    end

    def self.platform_scan(range:)
      new(range: range).scan
    end

    def self.account_scan(account_id:, range:)
      new(range: range, account_id: account_id).scan
    end

    # patra-final 5g (G45): READ-ONLY listing of the entries the scan counts
    # as malformed — mirrors ingest_contact/ingest_money_entry classification
    # exactly so the listing matches the "N malformed" warning. Never mutates.
    MALFORMED_REPORT_LIMIT = 200

    def self.malformed_report(limit: MALFORMED_REPORT_LIMIT)
      rows = []
      scope = Contact.where('custom_attributes ? :key', key: FINANCE_LOG_KEY)
                     .select(:id, :account_id, :custom_attributes)
      scope.find_each(batch_size: BATCH_SIZE) do |contact|
        collect_malformed_for_contact(contact, rows)
        break if rows.size >= limit
      end
      rows.first(limit)
    end

    def self.collect_malformed_for_contact(contact, rows)
      entries = (contact.custom_attributes || {})[FINANCE_LOG_KEY]
      unless entries.is_a?(Array)
        rows << malformed_row(contact, entries, 'finance log is not a list')
        return
      end

      parser = new(range: nil)
      entries.each do |raw|
        unless raw.is_a?(Hash)
          rows << malformed_row(contact, raw, 'entry is not a key/value row')
          next
        end
        next unless MONEY_KINDS.include?(raw['kind'].to_s)

        amount_bad = parser.send(:parse_amount, raw['amount']).nil?
        time_bad = parser.send(:parse_time, raw['logged_at']).nil?
        rows << malformed_row(contact, raw, [amount_bad ? 'unparseable amount' : nil, time_bad ? 'unparseable time' : nil].compact.join(' + ')) if amount_bad || time_bad
      end
    end

    def self.malformed_row(contact, raw, reason)
      {
        account_id: contact.account_id,
        contact_id: contact.id,
        raw: raw.inspect.to_s.truncate(160),
        logged_at: raw.is_a?(Hash) ? raw['logged_at'].to_s : '',
        reason: reason
      }
    end

    def scan
      acc = blank_accumulator
      contact_scope.find_each(batch_size: BATCH_SIZE) { |contact| ingest_contact(contact, acc) }

      {
        deposits: acc[:deposits],
        cashouts: acc[:cashouts],
        net: (acc[:deposits][:total] - acc[:cashouts][:total]).round(2),
        by_day: by_day_rows(acc[:by_day]),
        by_game: by_game_rows,
        top_accounts: top_account_rows(acc[:per_account]),
        risk: {
          flagged_players_total: acc[:flagged_players].values.sum,
          accounts_with_flagged: acc[:flagged_players].count { |_id, count| count.positive? },
          per_account: acc[:flagged_players]
        },
        malformed_count: acc[:malformed],
        scanned_contacts: acc[:scanned]
      }
    end

    private

    def blank_accumulator
      {
        deposits: { count: 0, total: 0.0 },
        cashouts: { count: 0, total: 0.0 },
        by_day: Hash.new { |h, k| h[k] = { deposits: 0.0, cashouts: 0.0 } },
        per_account: Hash.new { |h, k| h[k] = { deposits: 0.0, cashouts: 0.0 } },
        flagged_players: Hash.new(0),
        malformed: 0,
        scanned: 0
      }
    end

    def contact_scope
      scope = Contact.where('custom_attributes ? :key', key: FINANCE_LOG_KEY)
                     .select(:id, :account_id, :custom_attributes)
      scope = scope.where(account_id: @account_id) if @account_id
      scope
    end

    def ingest_contact(contact, acc)
      acc[:scanned] += 1
      entries = (contact.custom_attributes || {})[FINANCE_LOG_KEY]
      unless entries.is_a?(Array)
        acc[:malformed] += 1
        return
      end

      flagged = false
      entries.each do |raw|
        unless raw.is_a?(Hash)
          acc[:malformed] += 1
          next
        end

        flagged ||= raw['flag_reason'].to_s.strip.present? || raw['kind'].to_s == 'flagged'
        ingest_money_entry(raw, contact.account_id, acc)
      end
      acc[:flagged_players][contact.account_id] += 1 if flagged
    end

    def ingest_money_entry(entry, account_id, acc)
      kind = entry['kind'].to_s
      return unless MONEY_KINDS.include?(kind) # screenshot/status rows are normal, not malformed

      amount = parse_amount(entry['amount'])
      logged = parse_time(entry['logged_at'])
      if amount.nil? || logged.nil?
        acc[:malformed] += 1
        return
      end
      return unless @range.cover?(logged)

      bucket = kind == 'deposit' ? :deposits : :cashouts
      acc[bucket][:count] += 1
      acc[bucket][:total] = (acc[bucket][:total] + amount).round(2)
      acc[:by_day][logged.to_date][bucket] = (acc[:by_day][logged.to_date][bucket] + amount).round(2)
      acc[:per_account][account_id][bucket] = (acc[:per_account][account_id][bucket] + amount).round(2)
    end

    def by_day_rows(by_day)
      by_day.sort_by { |date, _| date }.map do |date, sums|
        { date: date, deposits: sums[:deposits], cashouts: sums[:cashouts], net: (sums[:deposits] - sums[:cashouts]).round(2) }
      end
    end

    # Pure SQL — successful load/cashout GameActions grouped by game.
    def by_game_rows
      scope = GameAction.where(status: 'success', action_type: %w[load cashout], created_at: @range)
      scope = scope.where(account_id: @account_id) if @account_id
      scope = scope.joins(agent_game: :game)

      sums = scope.group('games.name', :action_type).sum(:amount)
      counts = scope.group('games.name', :action_type).count

      sums.keys.map(&:first).uniq.sort.map do |game_name|
        loads = sums.fetch([game_name, 'load'], 0).to_f.round(2)
        cashouts = sums.fetch([game_name, 'cashout'], 0).to_f.round(2)
        {
          game: game_name,
          loads_total: loads,
          loads_count: counts.fetch([game_name, 'load'], 0),
          cashouts_total: cashouts,
          cashouts_count: counts.fetch([game_name, 'cashout'], 0),
          net: (loads - cashouts).round(2)
        }
      end
    end

    def top_account_rows(per_account)
      ranked = per_account.map do |account_id, sums|
        { account_id: account_id, deposits: sums[:deposits], cashouts: sums[:cashouts], net: (sums[:deposits] - sums[:cashouts]).round(2) }
      end
      ranked = ranked.sort_by { |row| -row[:net] }.first(TOP_ACCOUNTS)

      names = Account.where(id: ranked.map { |r| r[:account_id] }).pluck(:id, :name).to_h
      ranked.each { |row| row[:name] = names[row[:account_id]].to_s }
      ranked
    end

    def parse_amount(value)
      return value.to_f.round(2) if value.is_a?(Numeric) && value.to_f.positive?

      parsed = value.to_s.gsub(/[^\d.\-]/, '').to_f
      parsed.positive? ? parsed.round(2) : nil
    end

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
