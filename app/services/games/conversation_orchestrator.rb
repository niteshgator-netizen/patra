# Orchestrates the full game-related conversation flow.
# Called from reply_service.rb. Returns nil to let normal Bella handle the turn,
# or { reply:, labels: } when this orchestrator handled the intent.

module Games
  class ConversationOrchestrator
    attr_reader :account, :contact, :conversation, :messages

    def initialize(account:, contact:, conversation:, messages:)
      @account = account
      @contact = contact
      @conversation = conversation
      @messages = messages
    end

    # Main entrypoint. Returns nil if this orchestrator doesn't apply.
    def handle
      return nil unless account && contact

      latest_text = latest_customer_text
      combined_text = recent_customer_text
      probe_text = combined_text.presence || latest_text

      Rails.logger.info("[Orchestrator] handle starting account=#{account&.id} contact=#{contact&.id} latest=#{latest_text.to_s[0..100]} combined=#{combined_text.to_s[0..200]}")

      return nil if probe_text.blank?

      intent = Games::IntentDetector.detect(probe_text)
      Rails.logger.info("[Orchestrator] intent_detector returned: #{intent.inspect}")
      return nil if intent.nil?

      # Override game_slug with whatever is in the LATEST message — customer may have switched games
      latest_game = Games::IntentDetector.detect_game(latest_text)
      if latest_game && intent.is_a?(Hash)
        intent[:game_slug] = latest_game
        Rails.logger.info("[Orchestrator] overrode game_slug from latest message: #{latest_game}")
      end

      case intent[:intent]
      when :load
        handle_load_intent(intent)
      when :cashout
        handle_cashout_intent(intent)
      when :username_provided
        handle_username_provided(intent)
      when :request_account_creation
        handle_account_creation_request(intent)
      end
    rescue StandardError => e
      Rails.logger.error("[ConversationOrchestrator] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      begin
        Games::TelegramNotifier.api_error(account: account, message: "Orchestrator crashed", details: "#{e.class}: #{e.message}") if account
      rescue StandardError
        # never let notification failure crash anything
      end
      nil
    end

    private

    def handle_load_intent(intent)
      ag = pick_agent_game(intent[:game_slug] || 'game_vault')
      return nil unless ag

      requested_amount = intent[:amount].to_f

      # PAYMENT GATE: must have confirmed payment matching this amount
      payment = find_matching_confirmed_payment(requested_amount)

      unless payment
        # No payment yet — ask for it
        handle_text = active_payment_handle_for_account
        return {
          reply: payment_request_reply(requested_amount, handle_text, ag.game.name),
          labels: ['awaiting-payment']
        }
      end

      # Payment confirmed — now check username
      username = intent[:game_username] || stored_game_username(ag.game.slug)

      if username.blank?
        # Need to ask + offer auto-create
        return {
          reply: "got your $#{requested_amount} payment ✅ what username would you like on #{ag.game.name}? if you've never played, just pick one (3-20 letters/numbers) and i'll set up your account.",
          labels: ['needs-username']
        }
      end

      # Try to load. If username doesn't exist on Game Vault, auto-create it.
      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)

      result = executor.load_player(
        game_username: username,
        amount: requested_amount,
        payment_method: payment[:method],
        metadata: { source: 'bella_auto', payment_id: payment[:id], message: recent_customer_text.to_s[0..200] }
      )

      # Code 8 = user not found → auto-create + retry
      if !result[:ok] && result[:code] == 8
        Rails.logger.info("[Orchestrator] User #{username} not found, auto-creating")
        add_result = executor.add_player(game_username: username)

        if add_result[:ok]
          generated_password = add_result[:password]
          store_game_username(ag.game.slug, username)
          store_game_password(ag.game.slug, generated_password)

          # Retry the load now that user exists
          result = executor.load_player(
            game_username: username,
            amount: requested_amount,
            payment_method: payment[:method],
            metadata: { source: 'bella_auto_after_create', payment_id: payment[:id] }
          )

          if result[:ok]
            mark_payment_loaded(payment[:id])
            return {
              reply: "created your account! username: #{username}, password: #{generated_password} (save this!) — loaded $#{requested_amount} 🎰",
              labels: ['auto-load', 'new-account-created']
            }
          end
        else
          safe_telegram { Games::TelegramNotifier.load_failed(add_result[:action]) if add_result[:action] }
        end
      end

      # First-try result handling
      store_game_username(ag.game.slug, username)

      if result[:ok]
        mark_payment_loaded(payment[:id])
        {
          reply: "loaded $#{requested_amount} to #{username} on #{ag.game.name} 🎰 good luck!",
          labels: ['auto-load']
        }
      else
        safe_telegram { Games::TelegramNotifier.load_failed(result[:action]) if result[:action] }
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account,
            contact: contact,
            reason: "Load failed: #{result[:error]} (code #{result[:code]}) for #{username} $#{requested_amount}",
            conversation: conversation
          )
        end
        {
          reply: honest_failure_reply(result, requested_amount, ag.game.name),
          labels: ['load-failed', 'needs-human']
        }
      end
    end

    def handle_cashout_intent(intent)
      ag = pick_agent_game(intent[:game_slug] || 'game_vault')
      return nil unless ag

      username = intent[:game_username] || stored_game_username(ag.game.slug)
      if username.blank?
        return {
          reply: "got it — what's your username on #{ag.game.name}? need it to process your cashout.",
          labels: ['needs-username']
        }
      end

      deposit_amount = stored_deposit_amount || 5.0
      requested = intent[:amount]
      total_points = intent[:total_points] || requested

      calc = Games::CashoutCalculator.new(
        account: account,
        deposit_amount: deposit_amount,
        requested_amount: requested,
        total_points: total_points
      ).calculate

      if calc.cashout_amount <= 0
        return {
          reply: "you need at least #{calc.min_required ? "$#{calc.min_required}" : '4x'} in play to cashout. #{calc.explanation}",
          labels: ['cashout-not-eligible']
        }
      end

      cr = CashoutRequest.create!(
        account: account,
        agent_game: ag,
        contact: contact,
        conversation: conversation,
        player_name: contact.name,
        game_username: username,
        total_points: total_points,
        cashout_amount: calc.cashout_amount,
        remaining_points: calc.remaining_points,
        tip_amount: intent[:tip_amount] || 0,
        reload_amount: intent[:reload_amount] || 0,
        original_deposit: deposit_amount,
        deposit_payment_method: stored_payment_method,
        cashout_payment_method: intent[:cashout_method]&.dig(:platform),
        cashout_destination_handle: intent[:cashout_method]&.dig(:handle),
        applied_rules: calc.applied_rules,
        customer_message: recent_customer_text.to_s[0..500],
        status: 'pending'
      )

      begin
        Games::TelegramNotifier.cashout_alert(cr)
      rescue StandardError
      end

      # Auto-execute withdraw from game (the money still needs cashier approval to actually pay out)
      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)
      withdraw_result = executor.cashout_player(
        game_username: username,
        amount: calc.cashout_amount,
        metadata: { source: 'bella_auto', cashout_request_id: cr.id }
      )

      cr.update(withdraw_action_id: withdraw_result[:action]&.id) if withdraw_result[:action]

      begin
        Games::TelegramNotifier.cashout_failed(withdraw_result[:action], cr) if withdraw_result[:action] && !withdraw_result[:ok]
      rescue StandardError
      end

      if (intent[:reload_amount] || 0) > 0
        reload_result = executor.load_player(
          game_username: username,
          amount: intent[:reload_amount],
          metadata: { source: 'bella_auto_reload', cashout_request_id: cr.id }
        )
        cr.update(reload_action_id: reload_result[:action]&.id) if reload_result[:action]
      end

      reply_text = "got it — cashing out $#{calc.cashout_amount} for you. #{calc.explanation} a cashier will send the payment shortly."
      reply_text += " keeping $#{intent[:reload_amount]} loaded back on your game." if (intent[:reload_amount] || 0) > 0

      { reply: reply_text, labels: ['cashout-requested', 'cashier-action-needed'] }
    end

    def handle_username_provided(intent)
      ag = pick_agent_game(intent[:game_slug] || 'game_vault')
      return nil unless ag

      username = intent[:game_username]

      # Check if there's a confirmed payment waiting to be loaded
      recent_payment = find_unloaded_confirmed_payment
      return nil unless recent_payment # No pending action — let normal Bella handle

      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)

      # First try to load — if user doesn't exist, auto-create
      result = executor.load_player(
        game_username: username,
        amount: recent_payment[:amount],
        payment_method: recent_payment[:method],
        metadata: { source: 'bella_username_provided', payment_id: recent_payment[:id] }
      )

      if !result[:ok] && result[:code] == 8
        # User not found — create them
        add_result = executor.add_player(game_username: username)

        if add_result[:ok]
          password = add_result[:password]
          store_game_username(ag.game.slug, username)
          store_game_password(ag.game.slug, password)

          result = executor.load_player(
            game_username: username,
            amount: recent_payment[:amount],
            payment_method: recent_payment[:method],
            metadata: { source: 'bella_username_after_create', payment_id: recent_payment[:id] }
          )

          if result[:ok]
            mark_payment_loaded(recent_payment[:id])
            return {
              reply: "created your account! username: #{username}, password: #{password} (save this!) — loaded $#{recent_payment[:amount]} 🎰",
              labels: ['auto-load', 'new-account-created']
            }
          end
        else
          safe_telegram { Games::TelegramNotifier.load_failed(add_result[:action]) if add_result[:action] }
          safe_telegram do
            Games::TelegramNotifier.human_escalation(
              account: account, contact: contact,
              reason: "Failed to create user #{username}: #{add_result[:error]}",
              conversation: conversation
            )
          end
          return {
            reply: "hit a snag setting up your account — flagged a teammate, they'll get you sorted in a couple minutes.",
            labels: ['account-creation-failed', 'needs-human']
          }
        end
      end

      store_game_username(ag.game.slug, username)

      if result[:ok]
        mark_payment_loaded(recent_payment[:id])
        {
          reply: "loaded $#{recent_payment[:amount]} to #{username} on #{ag.game.name} 🎰 good luck!",
          labels: ['auto-load']
        }
      else
        safe_telegram { Games::TelegramNotifier.load_failed(result[:action]) if result[:action] }
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: "Load failed for #{username} $#{recent_payment[:amount]}: #{result[:error]}",
            conversation: conversation
          )
        end
        {
          reply: honest_failure_reply(result, recent_payment[:amount], ag.game.name),
          labels: ['load-failed', 'needs-human']
        }
      end
    end

    def handle_account_creation_request(intent)
      ag = pick_agent_game(intent[:game_slug] || 'game_vault')
      return nil unless ag

      # Check if customer wants to create a DIFFERENT account (replace existing)
      wants_replace = recent_customer_text.to_s.downcase.match?(/\b(diff(erent)?|another|new|change)\b.*\b(one|account|username)\b/) ||
                      recent_customer_text.to_s.downcase.match?(/\b(no|nah|nope|dont|don't)\b.*\b(use|like|want|that)\b/)

      # NO DUPLICATE ACCOUNTS — unless customer asked for a different one
      existing_username = stored_game_username(ag.game.slug)
      existing_password = stored_game_password(ag.game.slug)
      if existing_username.present? && !wants_replace
        handle_text = active_payment_handle_for_account
        reply = if existing_password.present?
          "you already have a #{ag.game.name} account! username: #{existing_username}, password: #{existing_password} 🎰 send your deposit to #{handle_text} and drop the screenshot here to load up."
        else
          "you already have a #{ag.game.name} account: #{existing_username}. send your deposit to #{handle_text} and drop the screenshot here to load up."
        end
        return { reply: reply, labels: ['account-exists', 'awaiting-payment'] }
      end

      # If replace requested, clear stored credentials so we generate fresh ones
      if existing_username.present? && wants_replace
        Rails.logger.info("[Orchestrator] customer requested replacement for #{ag.game.slug} — clearing old credentials from vault")
        clear_game_credentials(ag.game.slug)
      end

      # Check if customer has a confirmed payment waiting
      recent_payment = find_unloaded_confirmed_payment

      unless recent_payment
        # No payment yet — create account first, then ask for payment
        auto_username = generate_auto_username(ag.game.slug)
        executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)
        add_result = executor.add_player(game_username: auto_username)

        unless add_result[:ok]
          auto_username = generate_auto_username(ag.game.slug)
          add_result = executor.add_player(game_username: auto_username)
        end

        unless add_result[:ok]
          safe_telegram do
            Games::TelegramNotifier.human_escalation(
              account: account, contact: contact,
              reason: "Failed to auto-create username on #{ag.game.name}: #{add_result[:error]}",
              conversation: conversation
            )
          end
          return {
            reply: "hit a snag creating your account — flagged a teammate, they'll get you set up in a couple minutes.",
            labels: ['account-creation-failed', 'needs-human']
          }
        end

        generated_password = add_result[:password]
        store_game_username(ag.game.slug, auto_username)
        store_game_password(ag.game.slug, generated_password)
        handle_text = active_payment_handle_for_account

        return {
          reply: "all set! your username: #{auto_username}, password: #{generated_password} (save this!) — now send your deposit to #{handle_text} and drop the screenshot here, i'll load you up right away 🎰",
          labels: ['account-created', 'awaiting-payment']
        }
      end

      # Customer has confirmed payment — create account with auto-generated username
      auto_username = generate_auto_username(ag.game.slug)
      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)
      add_result = executor.add_player(game_username: auto_username)

      unless add_result[:ok]
        # Maybe collision — try one more time with different name
        auto_username = generate_auto_username(ag.game.slug)
        add_result = executor.add_player(game_username: auto_username)
      end

      unless add_result[:ok]
        safe_telegram { Games::TelegramNotifier.load_failed(add_result[:action]) if add_result[:action] }
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: "Failed to auto-create username on Game Vault: #{add_result[:error]}",
            conversation: conversation
          )
        end
        return {
          reply: "hit a snag creating your account — flagged a teammate, they'll get you set up in a couple minutes.",
          labels: ['account-creation-failed', 'needs-human']
        }
      end

      generated_password = add_result[:password]
      store_game_username(ag.game.slug, auto_username)
      store_game_password(ag.game.slug, generated_password)

      # Load the payment
      result = executor.load_player(
        game_username: auto_username,
        amount: recent_payment[:amount],
        payment_method: recent_payment[:method],
        metadata: { source: 'bella_account_created', payment_id: recent_payment[:id] }
      )

      if result[:ok]
        mark_payment_loaded(recent_payment[:id])
        {
          reply: "all set! username: #{auto_username}, password: #{generated_password} (save this!) — loaded $#{recent_payment[:amount]} 🎰 good luck!",
          labels: ['auto-load', 'new-account-created']
        }
      else
        safe_telegram { Games::TelegramNotifier.load_failed(result[:action]) if result[:action] }
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: "Created account #{auto_username} but load failed: #{result[:error]}",
            conversation: conversation
          )
        end
        {
          reply: "created your account! username: #{auto_username}, password: #{generated_password} (save this!) — but hit a snag loading your $#{recent_payment[:amount]}. a teammate will load it in a couple minutes.",
          labels: ['account-created', 'load-failed', 'needs-human']
        }
      end
    end

    GAME_SUFFIX_MAP = {
      'game_vault'      => 'gv',
      'juwa'            => 'jw',
      'juwa_2'          => 'jw2',
      'orion_stars'     => 'os',
      'fire_kirin'      => 'fk',
      'milky_way'       => 'mw',
      'vegas_sweeps'    => 'vs',
      'ultra_panda'     => 'up',
      'cash_frenzy'     => 'cf',
      'panda_master'    => 'pm',
      'river_sweeps'    => 'rs',
      'blue_dragon'     => 'bd',
      'golden_dragon'   => 'gd',
      'vegas_x'         => 'vx',
      'magic_city'      => 'mc',
      'lightning_link'  => 'll',
      'noble_sweeps'    => 'ns',
      'joker_mania'     => 'jm',
      'game_room'       => 'gr',
      'vblink'          => 'vb',
      'golden_treasure' => 'gt',
      'mr_all_in_one'   => 'ma',
      'bit_play'        => 'bp',
      'sirenis'         => 'si',
      'egame'           => 'eg',
      'cash_machine'    => 'cm',
      'spin_city'       => 'sc',
      'mafia'           => 'mf',
      'billion_balls'   => 'bb',
      'yolo'            => 'yo',
      'vegas_roll'      => 'vr'
    }.freeze

    def generate_auto_username(game_slug = nil)
      suffix = GAME_SUFFIX_MAP[game_slug.to_s] || game_slug.to_s.gsub('_', '')[0..1]
      base = (contact&.name.to_s.downcase.gsub(/[^a-z]/, '')[0..6])
      base = "player" if base.blank? || base.length < 3
      "#{base}#{SecureRandom.random_number(900) + 100}_#{suffix}"
    end

    def pick_agent_game(game_slug)
      ag = account.agent_games.joins(:game).where(games: { slug: game_slug }, status: 'active').first
      unless ag
        any_ag = account.agent_games.joins(:game).where(games: { slug: game_slug }).first
        Rails.logger.warn("[Orchestrator] pick_agent_game: no active agent_game for slug=#{game_slug} account=#{account.id} fallback_id=#{any_ag&.id.inspect} fallback_status=#{any_ag&.status.inspect}")
        ag = any_ag
      end
      ag
    end

    def latest_customer_text
      return nil unless messages.is_a?(Array)

      last = messages.reverse.find do |m|
        if m.is_a?(Hash)
          role = m[:role] || m['role']
          role.to_s == 'user'
        else
          m.respond_to?(:incoming?) && m.incoming?
        end
      end
      return nil unless last

      if last.is_a?(Hash)
        (last[:content] || last['content']).to_s
      else
        last.content.to_s
      end
    end

    def recent_customer_text
      # Returns concatenated content of the last 3 customer messages
      # to handle split intent like "Load me 20$ on" + "Game vault"
      return nil unless messages.is_a?(Array)

      customer_messages = messages.select do |m|
        if m.is_a?(Hash)
          role = m[:role] || m['role']
          role.to_s == 'user'
        else
          m.respond_to?(:incoming?) && m.incoming?
        end
      end

      return nil if customer_messages.empty?

      recent = customer_messages.last(3)
      texts = recent.map do |m|
        if m.is_a?(Hash)
          (m[:content] || m['content']).to_s
        else
          m.content.to_s
        end
      end

      texts.reject(&:blank?).join(' ').strip.presence
    end

    def stored_game_username(game_slug)
      key = "game_username_#{game_slug}"
      (contact.custom_attributes || {})[key]
    end

    def stored_game_password(game_slug)
      key = "game_password_#{game_slug}"
      (contact.custom_attributes || {})[key]
    end

    def store_game_username(game_slug, username)
      key = "game_username_#{game_slug}"
      attrs = (contact.custom_attributes || {}).merge(key => username)
      contact.update(custom_attributes: attrs)
    end

    def stored_deposit_amount
      (contact.custom_attributes || {})['last_deposit_amount']&.to_f
    end

    def stored_payment_method
      (contact.custom_attributes || {})['last_deposit_method']
    end

    def find_matching_confirmed_payment(requested_amount)
      logs = (contact.custom_attributes || {})['patra_finance_logs']
      return nil unless logs.is_a?(Array)

      logs.reverse.each do |log|
        next unless log.is_a?(Hash)

        # Status must be confirmed/completed/verified (case-insensitive)
        status = log['status'].to_s.downcase
        next unless %w[confirmed completed verified].include?(status)

        # CRITICAL: Reject flagged duplicates and anything with a flag_reason
        next if log['flag_reason'].to_s.strip.length > 0
        next if log['raw_status'].to_s.downcase == 'pending'

        amount = parse_amount(log['amount'])
        next if amount.nil? || amount <= 0

        time_str = log['recorded_at'] || log['image_received_at'] || log['transaction_time']
        recorded = parse_time(time_str)
        # TIGHTER WINDOW: 30 minutes, not 6 hours
        next if recorded && recorded < 30.minutes.ago

        log_id = log['id'] || log['transaction_id'] || "#{log['amount']}_#{log['recorded_at']}"
        next if payment_already_loaded?(log_id, amount, recorded)

        if (amount - requested_amount).abs < 0.01
          Rails.logger.info("[Orchestrator] matched payment id=#{log_id} amount=#{amount} for requested=#{requested_amount}")
          return { id: log_id, amount: amount, method: log['platform'], recorded_at: recorded }
        end
      end

      Rails.logger.info("[Orchestrator] no matching confirmed payment for requested=#{requested_amount}, log_count=#{logs.size}")
      nil
    end

    def find_unloaded_confirmed_payment
      logs = (contact.custom_attributes || {})['patra_finance_logs']
      return nil unless logs.is_a?(Array)

      logs.reverse.each do |log|
        next unless log.is_a?(Hash)

        status = log['status'].to_s.downcase
        next unless %w[confirmed completed verified].include?(status)

        # Reject flagged duplicates
        next if log['flag_reason'].to_s.strip.length > 0
        next if log['raw_status'].to_s.downcase == 'pending'

        amount = parse_amount(log['amount'])
        next if amount.nil? || amount <= 0

        time_str = log['recorded_at'] || log['image_received_at'] || log['transaction_time']
        recorded = parse_time(time_str)
        # TIGHTER WINDOW: 30 minutes, not 6 hours
        next if recorded && recorded < 30.minutes.ago

        log_id = log['id'] || log['transaction_id'] || "#{log['amount']}_#{log['recorded_at']}"
        next if payment_already_loaded?(log_id, amount, recorded)

        Rails.logger.info("[Orchestrator] found unloaded payment id=#{log_id} amount=#{amount}")
        return { id: log_id, amount: amount, method: log['platform'], recorded_at: recorded }
      end
      nil
    end

    def payment_already_loaded?(payment_id, amount, recorded_time)
      return true if GameAction
        .where(account_id: account.id, contact_id: contact.id, action_type: 'load', status: 'success')
        .where("metadata::text LIKE ?", "%#{payment_id}%")
        .exists?
      # Fallback: any successful load for this amount in the same window
      if recorded_time
        return GameAction
          .where(account_id: account.id, contact_id: contact.id, action_type: 'load', status: 'success', amount: amount)
          .where('created_at >= ?', recorded_time)
          .exists?
      end
      false
    end

    def mark_payment_loaded(payment_id)
      # Already tracked in metadata of game_actions, no contact mutation needed
      Rails.logger.info("[Orchestrator] payment #{payment_id} marked loaded")
    end

    def parse_amount(val)
      return nil if val.nil?
      val.to_s.gsub(/[^\d.]/, '').to_f.then { |f| f > 0 ? f : nil }
    end

    def parse_time(str)
      return nil if str.blank?
      Time.parse(str.to_s)
    rescue ArgumentError
      nil
    end

    def active_payment_handle_for_account
      if defined?(PaymentHandle)
        handle = PaymentHandle.where(account_id: account.id, status: 'active').order(:id).first
        return "#{handle.platform} #{handle.handle}" if handle
      end
      'the payment handle in our last message'
    end

    def payment_request_reply(amount, handle_text, game_name)
      "got it! send $#{amount} to #{handle_text}, then drop the screenshot here 📸 — i'll load it on #{game_name} as soon as it confirms."
    end

    def honest_failure_reply(result, amount, game_name)
      case result[:code]
      when 8
        "hmm — that username doesn't exist on #{game_name} yet. want me to create it? just confirm and i'll set you up."
      when 6
        "hit a temporary issue on our end — flagged a teammate, they'll load your $#{amount} in a couple minutes. you'll get a notification when it's done."
      when 5
        "couldn't reach #{game_name} just now — flagged a teammate to look at it, they'll have your $#{amount} loaded in a few minutes."
      else
        "ran into a snag loading your $#{amount} — flagged a teammate to handle it manually. they'll have you loaded in a couple minutes."
      end
    end

    def store_game_password(slug, password)
      key = "game_password_#{slug}"
      attrs = (contact.custom_attributes || {}).merge(key => password)
      contact.update(custom_attributes: attrs)
    end

    def clear_game_credentials(slug)
      attrs = (contact.custom_attributes || {}).dup
      attrs.delete("game_username_#{slug}")
      attrs.delete("game_password_#{slug}")
      contact.update(custom_attributes: attrs)
    end

    def safe_telegram
      yield
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] Telegram call failed: #{e.class}: #{e.message}")
    end

    # Looks at the most recent patra_finance_logs entry. If it's a confirmed deposit
    # less than 30 min old and has no matching load action yet, return its details.
    def recent_unloaded_deposit
      logs = (contact.custom_attributes || {})['patra_finance_logs']
      return nil unless logs.is_a?(Array) && logs.any?

      last = logs.last
      return nil unless last.is_a?(Hash)
      return nil unless %w[Confirmed completed].include?(last['status'].to_s)

      time_str = last['recorded_at'] || last['transaction_time']
      recorded = nil
      begin
        recorded = Time.parse(time_str.to_s) if time_str.present?
      rescue ArgumentError
        recorded = nil
      end

      return nil if recorded && recorded < 30.minutes.ago

      amount = last['amount']&.to_s&.gsub(/[^\d.]/, '')&.to_f
      return nil if amount.nil? || amount <= 0

      already_loaded = GameAction
                       .where(account_id: account.id, contact_id: contact.id, action_type: 'load', status: 'success')
                       .where('created_at >= ?', recorded || 1.hour.ago)
                       .where(amount: amount)
                       .exists?
      return nil if already_loaded

      { amount: amount, method: last['platform'] }
    end
  end
end
