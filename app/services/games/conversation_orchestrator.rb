# Orchestrates the full game-related conversation flow.
# Called from reply_service.rb. Returns nil to let normal Bella handle the turn,
# or { reply:, labels: } when this orchestrator handled the intent.

module Games
  class ConversationOrchestrator
    attr_reader :account, :contact, :conversation, :messages

    # Bug 1 fix: maps preferred_platform values from
    # players/profile_service.rb's PLATFORM_ALIASES to ClientRegistry game
    # slugs. preferred_platform stores 'milkyway' (no underscore) but
    # agent_games uses 'milky_way' (underscored). This bridges them.
    PREFERRED_PLATFORM_TO_SLUG = {
      'gamevault' => 'game_vault',
      'firekirin' => 'fire_kirin',
      'milkyway' => 'milky_way',
      'pandamaster' => 'panda_master',
      'orionstar' => 'orion_stars',
      'juwa' => 'juwa',
      'gameroom' => 'game_room',
      'cash_machine' => 'cash_machine',
      'mr_all_in_one' => 'mr_all_in_one',
      'ultra_panda' => 'ultra_panda',
      'vblink' => 'vblink',
      'vegas_sweeps' => 'vegas_sweeps',
      'mafia' => 'mafia'
    }.freeze

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

      # First check latest message alone — this is what the customer just asked NOW
      latest_intent = Games::IntentDetector.detect(latest_text)

      # Combined fallback ONLY for amount/cashout (split intent like "load 20$" + "on juwa")
      combined_intent = nil
      if latest_intent.nil? || (latest_intent.is_a?(Hash) && latest_intent[:intent] == :load && latest_intent[:amount].to_f <= 0)
        combined_intent = Games::IntentDetector.detect(combined_text)
      end

      # Choose: prefer latest_intent, fall back to combined only if latest was empty
      intent = latest_intent || combined_intent
      Rails.logger.info("[Orchestrator] intent latest=#{latest_intent.inspect} combined=#{combined_intent.inspect} chosen=#{intent.inspect}")
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
      when :payment_method_chosen
        handle_payment_method_chosen(intent)
      when :reset_password
        handle_reset_password_intent(intent)
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
      ag = pick_agent_game(chosen_game_slug(intent))
      return nil unless ag

      requested_amount = intent[:amount].to_f

      # PAYMENT GATE: must have confirmed payment matching this amount
      payment = find_matching_confirmed_payment(requested_amount)

      unless payment
        # No payment yet — ask for it. Bug 7 fix: pass the default active
        # platform so the reply format matches handle_payment_method_chosen.
        handle_text = active_payment_handle_for_account
        default_platform =
          begin
            active_payment_platforms.first.to_s
          rescue StandardError
            ''
          end
        return {
          reply: payment_request_reply(requested_amount, handle_text, default_platform, ag.game.name),
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
        add_result = executor.add_player(game_username: username, password: password_from_username(username))

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
      ag = pick_agent_game(chosen_game_slug(intent))
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
      ag = pick_agent_game(chosen_game_slug(intent))
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
        add_result = executor.add_player(game_username: username, password: password_from_username(username))

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
      ag = pick_agent_game(chosen_game_slug(intent))
      return nil unless ag

      # Check if customer wants to create a DIFFERENT account (replace existing)
      wants_replace = recent_customer_text.to_s.downcase.match?(/\b(diff(erent)?|another|new|change)\b.*\b(one|account|username)\b/) ||
                      recent_customer_text.to_s.downcase.match?(/\b(no|nah|nope|dont|don't)\b.*\b(use|like|want|that)\b/)

      # NO DUPLICATE ACCOUNTS — unless customer asked for a different one
      existing_username = stored_game_username(ag.game.slug)
      existing_password = stored_game_password(ag.game.slug)
      if existing_username.present? && !wants_replace
        methods_q = payment_methods_question
        reply = if existing_password.present?
          "you already have a #{ag.game.name} account! username: #{existing_username}, password: #{existing_password} 🎰 #{methods_q}"
        else
          "you already have a #{ag.game.name} account: #{existing_username}. #{methods_q}"
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
        auto_password = password_from_username(auto_username, ag.game.slug)
        executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)
        add_result = executor.add_player(game_username: auto_username, password: auto_password)

        unless add_result[:ok]
          auto_username = generate_auto_username(ag.game.slug)
          auto_password = password_from_username(auto_username, ag.game.slug)
          add_result = executor.add_player(game_username: auto_username, password: auto_password)
        end

        # CRITICAL: if add_player still failed after retry, DO NOT lie and say "all set"
        unless add_result[:ok]
          Rails.logger.error("[Orchestrator] add_player failed for #{ag.game.name} after 2 retries: #{add_result[:error]}")
          safe_telegram do
            Games::TelegramNotifier.human_escalation(
              account: account, contact: contact,
              reason: "Failed to auto-create username on #{ag.game.name}: #{add_result[:error]}",
              conversation: conversation
            )
          end
          return {
            reply: "hit a snag setting up your #{ag.game.name} account — flagged a teammate, they'll get you sorted in a couple minutes.",
            labels: ['account-creation-failed', 'needs-human']
          }
        end

        generated_password = add_result[:password]
        store_game_username(ag.game.slug, auto_username)
        store_game_password(ag.game.slug, generated_password)

        return {
          reply: "all set! your username: #{auto_username}, password: #{generated_password} (save this!) — #{payment_methods_question}",
          labels: ['account-created', 'awaiting-payment']
        }
      end

      # Customer has confirmed payment — create account with auto-generated username
      auto_username = generate_auto_username(ag.game.slug)
      auto_password = password_from_username(auto_username, ag.game.slug)
      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)
      add_result = executor.add_player(game_username: auto_username, password: auto_password)

      unless add_result[:ok]
        # Maybe collision — try one more time with different name
        auto_username = generate_auto_username(ag.game.slug)
        auto_password = password_from_username(auto_username, ag.game.slug)
        add_result = executor.add_player(game_username: auto_username, password: auto_password)
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

    # Slugs whose panels require strong passwords on RESET only (upper+lower+special, 6-12 chars).
    # Verified May 19 2026 against live Mafia panel error message; same Laravel/layui codebase
    # for all 4 Cluster 2 panels, so they share this rule.
    CLUSTER_2_RESET_STRONG_PW = %w[mafia game_room cash_machine mr_all_in_one].freeze

    # Bug fix May 19 2026: Cluster 2 Laravel panels reject usernames with
    # underscores ("letters and numbers only, 5-20 chars"). We use this set
    # to choose the username format in generate_auto_username and to know
    # how to extract the password back out via password_from_username.
    # Same 4 slugs as CLUSTER_2_RESET_STRONG_PW — kept as a separate
    # constant for clarity in case username rules diverge from reset rules.
    CLUSTER_2_SLUGS = %w[mafia game_room cash_machine mr_all_in_one].freeze

    # Bug fix May 20 2026: FastApi panels (VBLink, Ultra Panda) also reject
    # underscores in usernames — provider returns code 7 "Username can only be
    # alphanumeric". Diagnosed via direct API test in Rails console.
    # USERNAME_NO_UNDERSCORE_SLUGS is the full set of panels requiring the
    # no-underscore username format; supersedes CLUSTER_2_SLUGS for that purpose.
    USERNAME_NO_UNDERSCORE_SLUGS = (CLUSTER_2_SLUGS + %w[vblink ultra_panda]).freeze

    # Bug fix May 19 2026: format diverges by cluster.
    #   Cluster 1 (game_vault, juwa, milky_way, fire_kirin, panda_master, orion_stars):
    #     "mausam397_jw" — underscore separator allowed, easy to extract password from.
    #   Cluster 2 (mafia, game_room, cash_machine, mr_all_in_one):
    #     "mausam397gr"  — NO underscore, panel rejects it (letters+numbers only).
    # password_from_username has matching logic to extract the password back out.
    def generate_auto_username(game_slug = nil)
      suffix = GAME_SUFFIX_MAP[game_slug.to_s] || game_slug.to_s.gsub('_', '')[0..1]
      base = (contact&.name.to_s.downcase.gsub(/[^a-z]/, '')[0..6])
      base = "player" if base.blank? || base.length < 3
      number = SecureRandom.random_number(900) + 100

      if USERNAME_NO_UNDERSCORE_SLUGS.include?(game_slug.to_s)
        "#{base}#{number}#{suffix}"
      else
        "#{base}#{number}_#{suffix}"
      end
    end

    # Extracts the password (base + number) from an auto-generated username.
    # Mirrors generate_auto_username's two formats:
    #   Cluster 1 etc:  "mausam963_jw" -> "mausam963" (split on underscore)
    #   Cluster 2:      "mausam963gr"  -> "mausam963" (strip trailing 2-3 alpha chars)
    # game_slug is optional but REQUIRED for correct Cluster 2 extraction; without
    # it we fall back to the legacy underscore-split which is correct for everything
    # except Cluster 2 (where the username has no underscore at all).
    def password_from_username(username, game_slug = nil)
      if game_slug.present? && USERNAME_NO_UNDERSCORE_SLUGS.include?(game_slug.to_s)
        username.to_s.sub(/[a-z]{2,3}\z/i, '')
      else
        username.to_s.split('_').first || username.to_s
      end
    end

    # Generate a compliant new password for a password reset on the given game.
    # Format mirrors the create-time pattern (firstname + 3-digit number) but adapts
    # to per-game rules:
    #   - Cluster 2 panels (Mafia/Gameroom/Cashmachine/MrAllInOne): require upper+lower+special, max 12 chars
    #     -> "Mausa!412" pattern (capitalize first letter, insert "!", ~9 chars)
    #   - Everything else: alphanumeric 6+ chars
    #     -> "mausam412" pattern (same as create)
    def generate_reset_password(game_slug)
      base = contact&.name.to_s.downcase.gsub(/[^a-z]/, '')[0..5]
      base = 'player' if base.blank? || base.length < 3
      num  = SecureRandom.random_number(900) + 100

      if CLUSTER_2_RESET_STRONG_PW.include?(game_slug.to_s)
        # Capitalize first char, trim to 5 chars to leave room for "!" + 3 digits = 9 total (under 12 limit)
        short_base = base[0..4]
        "#{short_base.capitalize}!#{num}"
      else
        # Alphanumeric format, identical to create-time password
        "#{base}#{num}"
      end
    end

    # Bug 1 fix: picks the game slug in priority order:
    #   1. intent[:game_slug] from latest message detection
    #   2. contact.custom_attributes['preferred_platform'] (auto-detected
    #      from history by Players::ProfileService)
    #   3. 'game_vault' (legacy default — last resort)
    # Bug fix May 20 2026: return nil instead of falling back to 'game_vault'
    # when the slug genuinely can't be resolved. The old hardcoded 'game_vault'
    # default caused every typo or unknown game name (e.g. "firekirrin" with
    # two Rs) to silently route to Game Vault. Since Game Vault is currently
    # broken (token invalid waiting on provider), customers got a confusing
    # "hit a snag setting up your Game Vault account" reply when they actually
    # asked for Fire Kirin. Returning nil lets Bella handle it naturally
    # instead of confidently wrong-routing.
    def chosen_game_slug(intent)
      explicit = intent.is_a?(Hash) ? intent[:game_slug] : nil
      return explicit if explicit.present?

      preferred = (contact&.custom_attributes || {})['preferred_platform'].to_s.downcase.strip
      mapped = PREFERRED_PLATFORM_TO_SLUG[preferred]
      return mapped if mapped.present?

      nil
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

    # Returns array of unique active platforms for this account, e.g. ["cashapp", "paypal", "venmo", "chime"]
    def active_payment_platforms
      return [] unless defined?(PaymentHandle)
      PaymentHandle.where(account_id: account.id, status: 'active')
                   .pluck(:platform).uniq
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] active_payment_platforms failed: #{e.class}: #{e.message}")
      []
    end

    # Returns the top-priority active display_name (e.g. "$sofiamann8") for the given platform.
    # Returns nil if no active handle exists for that platform.
    def top_handle_for_platform(platform)
      return nil unless defined?(PaymentHandle)
      ph = PaymentHandle.where(account_id: account.id, platform: platform.to_s, status: 'active')
                        .order(:priority).first
      return nil unless ph
      ph.respond_to?(:display_handle) ? ph.display_handle : (ph.try(:display_name).presence || ph.try(:handle))
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] top_handle_for_platform(#{platform}) failed: #{e.class}: #{e.message}")
      nil
    end

    # Returns the "which method?" question, dynamically built from active platforms.
    # Falls back to the single-handle string if no platforms are configured.
    def payment_methods_question
      platforms = active_payment_platforms
      return "send your deposit to #{active_payment_handle_for_account} and drop the screenshot here" if platforms.empty?

      pretty = platforms.map do |p|
        case p.to_s.downcase
        when 'cashapp' then 'cashapp'
        when 'chime'   then 'chime'
        when 'venmo'   then 'venmo'
        when 'paypal'  then 'paypal'
        when 'zelle'   then 'zelle'
        else p.to_s
        end
      end

      list = if pretty.size == 1
               pretty.first
             elsif pretty.size == 2
               pretty.join(' or ')
             else
               "#{pretty[0..-2].join(', ')}, or #{pretty.last}"
             end

      "we got #{list} 🙌 which one you wanna use?"
    end

    # Handler for when the customer picks a payment method ("paypal", "i'll use cashapp", etc.)
    # Looks up the top-priority active handle for that platform and replies with it.
    def handle_payment_method_chosen(intent)
      platform = intent[:platform].to_s.downcase.strip
      handle_text = top_handle_for_platform(platform)

      unless handle_text
        Rails.logger.warn("[Orchestrator] payment_method_chosen no active handle for platform=#{platform}")
        return {
          reply: payment_methods_question,
          labels: ['payment-method-unavailable']
        }
      end

      Rails.logger.info("[Orchestrator] payment_method_chosen platform=#{platform} handle=#{handle_text}")
      {
        reply: "easy! send to #{handle_text} on #{platform} and drop the screenshot here 📸",
        labels: ['payment-method-chosen', "payment-#{platform}"]
      }
    end

    # Customer asked to reset their password on a game.
    # Required intent fields: :game_slug (string slug like 'mafia')
    # Optional intent fields: :game_username (string), :new_password (string, customer-supplied)
    # Falls back to stored username and auto-generated password if not provided.
    def handle_reset_password_intent(intent)
      game_slug = intent[:game_slug]
      ag = pick_agent_game(game_slug) if game_slug.present?
      ag ||= account.agent_games.joins(:game).where(status: 'active').first

      unless ag
        return {
          reply: "which game do you want me to reset? (juwa, milky way, mafia, etc.)",
          labels: ['reset-needs-game']
        }
      end

      # Resolve the username: explicit > stored. Don't auto-create here — reset on a
      # nonexistent account is wrong, the customer should request account creation instead.
      username = intent[:game_username].presence || stored_game_username(ag.game.slug)

      if username.blank?
        return {
          reply: "what's your #{ag.game.name} username? need it to reset your password.",
          labels: ['reset-needs-username']
        }
      end

      # Generate or accept the new password. Customer-supplied passwords are not honored yet
      # (panels have strict rules and customers tend to pick noncompliant ones). Always auto-generate.
      new_password = generate_reset_password(ag.game.slug)

      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)
      result = executor.reset_player_password(
        game_username: username,
        new_password: new_password,
        metadata: { source: 'bella_auto_reset', conversation_id: conversation&.id }
      )

      if result[:ok]
        store_game_password(ag.game.slug, new_password)
        {
          reply: "your new #{ag.game.name} password is #{new_password} — save this! 🎰",
          labels: ['password-reset']
        }
      else
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: "Password reset failed on #{ag.game.name} for #{username}: #{result[:error]}",
            conversation: conversation
          )
        end
        {
          reply: "hit a snag resetting your #{ag.game.name} password — flagged a teammate, they'll handle it shortly.",
          labels: ['reset-failed', 'needs-human']
        }
      end
    end

    # Bug 7 fix: payment_request_reply now mirrors handle_payment_method_chosen
    # by including the platform ("send $5 to X on cashapp"). If platform is
    # blank or handle_text already contains the platform name (legacy single-
    # handle format like "cashapp sofia mann"), we skip the suffix to avoid
    # duplicates ("send $5 to cashapp sofia mann on cashapp" would be ugly).
    def payment_request_reply(amount, handle_text, platform, game_name)
      handle_str = handle_text.to_s.strip
      platform_str = platform.to_s.strip.downcase
      already_has_platform = platform_str.present? && handle_str.downcase.include?(platform_str)

      suffix = (platform_str.present? && !already_has_platform) ? " on #{platform_str}" : ''

      "got it! send $#{amount} to #{handle_str}#{suffix}, then drop the screenshot here 📸 — i'll load it on #{game_name} as soon as it confirms."
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
