# Detects load/cashout intents from customer messages.
# Returns { intent:, amount:, game_username: } or nil.
# Used by ConversationOrchestrator.

module Games
  class IntentDetector
    LOAD_PATTERNS = [
      /load\s+(?:me\s+)?\$?(\d+(?:\.\d{1,2})?)/i,
      /add\s+\$?(\d+(?:\.\d{1,2})?)/i,
      /recharge\s+\$?(\d+(?:\.\d{1,2})?)/i,
      /top\s*up\s+\$?(\d+(?:\.\d{1,2})?)/i,
      /deposit\s+\$?(\d+(?:\.\d{1,2})?)/i,
      /load\s+(\d+(?:\.\d{1,2})?)\$?\s+(?:on|to|for|in)\s+([a-z0-9_]{3,20})/i,
      /(\d+(?:\.\d{1,2})?)\s*\$?\s+(?:on|to|for|in)\s+([a-z0-9_]{3,20})/i,
      # Amount-less: "load please on gameroom", "load it", "load on juwa", "load me up"
      /\b(?:load|recharge|top\s*up)\b(?:\s+(?:me|it|please|up|now|my\s+account))*(?:\s+(?:on|to|for|in)\s+[a-z0-9_]{3,20})?/i,
      # "put 5 on gv" — imperative load via "put" (game token like "gv" is only 2 chars,
      # so the bare-number fallback's {3,20} can't catch it). Captures the amount; the
      # game is resolved separately by detect_game.
      /put\s+(?:me\s+)?\$?(\d+(?:\.\d{1,2})?)/i
    ].freeze

    FREEPLAY_PATTERNS = [
      /\bfree\s*play\b/i,
      /\bfp\b/i,
      /\bfreeplay\b/i
    ].freeze

    BONUS_PATTERNS = [
      /\bbonus\b/i,
      /\bpromo\b/i,
      /\bpromotion\b/i
    ].freeze

    # ---- Info / link / question intents (Batch: AI brain completion) ----
    # Placed as their own constants; detection branches are ordered in detect()
    # to avoid stealing from LOAD / CREATE / CASHOUT / payment-pick.
    REQUEST_GAME_LINK_PATTERNS = [
      /\blink\s+to\s+play\b/i,
      /\bwhere\s+(?:do|can)\s+i\s+play\b/i,
      /\b(?:web|game)\s+link\b/i,
      /\bplay\s+online\b/i,
      /\b(?:web\s*site|the\s+site|site\s+link)\b/i,
      /\blink\s+(?:to|for)\s+(?:the\s+)?(?:game|play)/i
    ].freeze

    REQUEST_DOWNLOAD_LINK_PATTERNS = [
      /\bdownload\b/i,
      /\bapk\b/i,
      /\binstall\b/i,
      /\bwhere\s+(?:to|do\s+i)\s+download\b/i
    ].freeze

    REQUEST_APP_LINK_PATTERNS = [
      /\bapp\s+link\b/i,
      /\bsend\s+(?:me\s+)?(?:the\s+)?app\b/i,
      /\bget\s+(?:the\s+)?app\b/i,
      /\b(?:the|your|that)\s+app\b/i
    ].freeze

    # Asking ABOUT cashout limits — NOT requesting a cashout. Checked BEFORE
    # CASHOUT_PATTERNS so "how much can i cash out" / "minimum cashout" don't
    # become an actual :cashout. Requires a min/max/limit/rules word, so a real
    # "cash out 50" or "i wanna cash out" never matches here.
    CASHOUT_RULES_PATTERNS = [
      /cash\s*out\s+rules?/i,
      /(?:minimum|min|max|maximum)\s+(?:cash\s*out|cashout|redeem|withdraw)/i,
      /(?:cash\s*out|cashout|redeem|withdraw)\s+(?:minimum|min|max|maximum|limit|rules?)/i,
      /how\s+much\s+(?:can|do)\s+i\s+(?:cash\s*out|cashout|redeem|withdraw)/i,
      /withdrawal\s+limit/i,
      /min(?:imum)?\s+to\s+redeem/i
    ].freeze

    LIST_PLATFORMS_PATTERNS = [
      /\bwhat\s+games?\b/i,
      /\bwhich\s+games?\b/i,
      /\bwhat\s+platforms?\b/i,
      /\bgames?\s+do\s+you\s+have\b/i,
      /\blist\s+games?\b/i,
      /\bwhat\s+do\s+you\s+have\b/i
    ].freeze

    # Asking ABOUT payment methods — NOT choosing one. PAYMENT_METHOD_PICK_PATTERNS
    # require a platform name (cashapp/venmo/...), so a generic "what payment
    # methods?" never matches a pick; these only catch the generic question forms.
    PAYMENT_METHOD_QUESTION_PATTERNS = [
      /\bwhat\s+payment/i,
      /\bhow\s+(?:can|do)\s+i\s+pay\b/i,
      /\bpayment\s+(?:methods?|options?)\b/i,
      /\bwhat\s+do\s+you\s+accept\b/i,
      /\bhow\s+(?:can|do)\s+i\s+(?:send|deposit)\b/i
    ].freeze

    CASHOUT_PATTERNS = [
      /cash\s*out\s+\$?(\d+(?:\.\d{1,2})?)/i,
      /cashout\s+\$?(\d+(?:\.\d{1,2})?)/i,
      /redeem\s+\$?(\d+(?:\.\d{1,2})?)/i,
      /withdraw\s+\$?(\d+(?:\.\d{1,2})?)/i,
      /payout\s+\$?(\d+(?:\.\d{1,2})?)/i,
      /i\s+(?:want\s+|wanna\s+)?(?:to\s+)?(?:cash\s*out|cashout|redeem|withdraw)/i
    ].freeze

    USERNAME_PATTERNS = [
      /(?:username|user)\s*:?\s*([a-z0-9_]{3,30})/i,
      /(?:on\s+game\s*vault|on\s+gv)\s*:?\s*([a-z0-9_]{3,30})/i,
      /my\s+(?:username|name|user|account)\s+is\s+([a-z0-9_]{3,30})/i,
      /i'?m\s+([a-z0-9_]{3,30})\s+on/i
    ].freeze

    GAME_NAME_ALIASES = {
      # Juwa 2 — longest aliases first at runtime via sort_by(-length)
      'juwa 2.0' => 'juwa_2',
      'juuwa 2' => 'juwa_2',
      'juwa two' => 'juwa_2',
      'jua 2' => 'juwa_2',
      'juw 2' => 'juwa_2',
      'juwa 2' => 'juwa_2',
      'juwa2' => 'juwa_2',
      'jw2' => 'juwa_2',
      'juwa_2' => 'juwa_2',

      # Juwa
      'juwa 1' => 'juwa',
      'juuwa' => 'juwa',
      'juwaa' => 'juwa',
      'juwa1' => 'juwa',
      'jua' => 'juwa',
      'juw' => 'juwa',
      'juwa' => 'juwa',

      # Fire Kirin
      'fire kirin' => 'fire_kirin',
      'fire kiren' => 'fire_kirin',
      'fire kirn' => 'fire_kirin',
      'fire krin' => 'fire_kirin',
      'firekirrin' => 'fire_kirin',
      'firekiren' => 'fire_kirin',
      'firekirin' => 'fire_kirin',
      'firekrin' => 'fire_kirin',
      'fire_kirin' => 'fire_kirin',
      'fk' => 'fire_kirin',

      # Milky Way
      'milky way' => 'milky_way',
      'milkeyway' => 'milky_way',
      'milkyway' => 'milky_way',
      'milkway' => 'milky_way',
      'milky_way' => 'milky_way',
      'milky' => 'milky_way',
      'mw' => 'milky_way',

      # Game Vault
      'game vault' => 'game_vault',
      'game volt' => 'game_vault',
      'gamevault' => 'game_vault',
      'gamevolt' => 'game_vault',
      'game_vault' => 'game_vault',
      'vault' => 'game_vault',
      'gv' => 'game_vault',

      # Vegas Sweeps
      'vegas sweeps' => 'vegas_sweeps',
      'vega sweeps' => 'vegas_sweeps',
      'vegassweeps' => 'vegas_sweeps',
      'vegasweeps' => 'vegas_sweeps',
      'vegas_sweeps' => 'vegas_sweeps',
      'vegas' => 'vegas_sweeps',
      'vs' => 'vegas_sweeps',

      # Orion Stars
      'orion stars' => 'orion_stars',
      'orian stars' => 'orion_stars',
      'orien stars' => 'orion_stars',
      'orionstars' => 'orion_stars',
      'orion_stars' => 'orion_stars',
      'orion' => 'orion_stars',
      'os' => 'orion_stars',

      # Panda Master
      'panda master' => 'panda_master',
      'pandamaster' => 'panda_master',
      'pandmaster' => 'panda_master',
      'panda_master' => 'panda_master',
      'panda' => 'panda_master',
      'pm' => 'panda_master',

      # Mafia
      'mafia777' => 'mafia',
      'maffia' => 'mafia',
      'mafia' => 'mafia',

      # Ultra Panda
      'ultra panda' => 'ultra_panda',
      'ultrapanda' => 'ultra_panda',
      'ultra_panda' => 'ultra_panda',
      'ultra' => 'ultra_panda',

      # VBLink
      'v b link' => 'vblink',
      'vb link' => 'vblink',
      'vblink' => 'vblink',
      'vb' => 'vblink',

      # Cash Machine
      'cash machine' => 'cash_machine',
      'cashmachine' => 'cash_machine',
      'cash_machine' => 'cash_machine',
      'cm' => 'cash_machine',

      # Game Room
      'game room' => 'game_room',
      'game rom' => 'game_room',
      'gameroom' => 'game_room',
      'game_room' => 'game_room',
      'gr' => 'game_room',

      # Mr All In One
      'mr all in one' => 'mr_all_in_one',
      'mrallinone' => 'mr_all_in_one',
      'mr_all_in_one' => 'mr_all_in_one',
      'mrallnone' => 'mr_all_in_one',
      'all in one' => 'mr_all_in_one',
      'allinone' => 'mr_all_in_one'
    }.freeze

    # Maps game slug -> array of lowercase substring keywords that, if found in customer text,
    # identify the game. Multi-word keywords use space-separated values.
    # Order matters: longer/more-specific keywords should come first within each list to avoid
    # false matches (e.g. "kirin" before "fire" so "fire kirin" doesn't double-match).
    # Slugs MUST match the slug column in the games table (verified via Games::ClientRegistry).
    GAME_KEYWORDS = {
      'game_vault'    => ['gamevault', 'game vault', 'gv'],
      'juwa_2'        => ['juwa 2.0', 'juwa 2', 'juwa2', 'juwa two'],
      'juwa'          => ['juwa'],
      'orion_stars'   => ['orionstars', 'orion stars', 'orion'],
      'fire_kirin'    => ['firekirin', 'fire kirin'],
      'milky_way'     => ['milkyway', 'milky way'],
      'panda_master'  => ['pandamaster', 'panda master', 'panda'],
      'mafia'         => ['mafia'],
      'game_room'     => ['gameroom', 'game room'],
      'cash_machine'  => ['cashmachine', 'cash machine'],
      'mr_all_in_one' => ['mrallinone', 'mr all in one', 'mr allinone', 'all in one'],
      'ultra_panda'   => ['ultrapanda', 'ultra panda', 'ultra_panda'],
      'vblink'        => ['vblink', 'v blink', 'v-blink'],
      'vegas_sweeps'  => ['vegassweeps', 'vegas sweeps']
    }.freeze

    POINTS_PATTERNS = [
      /(?:i\s+have|got|earned|made|got\s+to|hit|at)\s+\$?(\d+(?:\.\d{1,2})?)\s*(?:points?|pts?)?/i,
      /(?:i\s+won|won)\s+\$?(\d+(?:\.\d{1,2})?)/i
    ].freeze

    TIP_PATTERNS = [
      /(?:and\s+)?tip\s+\$?(\d+(?:\.\d{1,2})?)/i
    ].freeze

    RELOAD_PATTERNS = [
      /(?:and\s+)?reload\s+\$?(\d+(?:\.\d{1,2})?)/i,
      /(?:and\s+)?keep\s+\$?(\d+(?:\.\d{1,2})?)\s+in/i
    ].freeze

    CASHOUT_METHOD_PATTERNS = [
      /(?:(?:via|to|on|using)\s+)?(?:my\s+)?(?:cashapp|cash\s*app)\s*(?:is\s+|tag\s+|handle\s+|:\s*)?([\$\@]?[a-zA-Z0-9_]{3,30})/i,
      /(?:(?:via|to|on|using)\s+)?(?:my\s+)?(?:chime|venmo|paypal|zelle)\s*(?:is\s+|tag\s+|handle\s+|:\s*)?([\$\@]?[a-zA-Z0-9_.@+]{3,50})/i,
      /send\s+(?:it\s+)?to\s+([\$\@][a-zA-Z0-9_]{3,30})/i
    ].freeze

    GREETING_PATTERNS = /\A\s*(hey|hi|hello|yo|sup|what'?s?\s*up|wh?assup|howdy|hola)\b/i

    CREATE_ACCOUNT_PATTERNS = [
      /create\s+(?:me\s+)?(?:an?\s+)?(?:new\s+)?(?:.+\s+)?(?:username|user|account|profile|login|it)/i,
      /create\s+me\s+one\b/i,
      /create\s+me\s+an?\s+account\b/i,
      /create\s+one\s+for\s+me\b/i,
      /make\s+(?:me\s+)?(?:a\s+)?(?:new\s+)?(?:.+\s+)?(?:username|user|account)/i,
      /make\s+me\s+one\b/i,
      /make\s+me\s+an?\s+account\b/i,
      /make\s+one\s+for\s+me\b/i,
      /(?:i\s+)?need\s+(?:an?\s+)?(?:new\s+)?(?:.+\s+)?(?:username|user|account)/i,
      /(?:can\s+you\s+)?sign\s+me\s+up/i,
      /\bsign\s+up\b/i,
      /register\s+me\b/i,
      /set\s+(?:me\s+)?up\s+(?:a\s+)?(?:new\s+)?(?:.+\s+)?(?:account|username)/i,
      /set\s+me\s+up\b/i,
      /set\s+up\s+an?\s+account\b/i,
      /set\s+up\s+my\s+account\b/i,
      /never\s+played\s+(?:before|here)/i,
      /first\s+time\s+(?:playing|here)/i,
      /(?:i\s+)?don'?t\s+have\s+(?:a\s+)?(?:username|account)/i,
      /(?:i\s+)?don'?t\s+have\s+one\b/i,
      /dont\s+have\s+one\b/i,
      /(?:set\s+it\s+up|set\s+me\s+up)/i,
      /give\s+me\s+(?:an?\s+)?(?:new\s+)?(?:.+\s+)?account/i,
      /give\s+me\s+one\b/i,
      /(?:i\s+)?want\s+(?:an?\s+)?(?:new\s+)?(?:.+\s+)?account/i,
      /i\s+want\s+an?\s+account\b/i,
      /i\s+need\s+an?\s+account\b/i,
      /i\s+need\s+one\b/i,
      /get\s+me\s+an?\s+account\b/i,
      /can\s+you\s+create\b/i,
      /can\s+you\s+make\b/i,
      /can\s+i\s+get\s+an?\s+account\b/i,
      /\bnew\s+account\b/i,
      /open\s+an?\s+account\b/i,
      /(?:i\s+)?(?:want|wanna|need)\s+(?:to\s+)?(?:join|start|play|get\s+(?:in|started))/i,
      /(?:can\s+i\s+)?get\s+(?:me\s+)?(?:a\s+|an\s+)?(?:new\s+)?(?:.+\s+)?(?:username|user|account|profile|login)/i,
      /make\s+(?:me\s+)?(?:a\s+)?(?:brand\s+)?(?:new\s+)?(?:.+\s+)?account/i,
      /(?:hook|set)\s+me\s+up/i,
      /hook\s+me\s+up\b/i
    ].freeze

    # Customer asks to reset their game password. Multiple natural phrasings.
    # These patterns intentionally do NOT capture the new password — orchestrator auto-generates
    # one that complies with per-panel rules (Cluster 2 needs upper+lower+special, etc).
    RESET_PASSWORD_PATTERNS = [
      /reset\s+(?:my\s+)?(?:pw|password|pass)/i,
      /change\s+(?:my\s+)?(?:pw|password|pass)/i,
      /(?:new|fresh)\s+(?:pw|password|pass)/i,
      /forgot\s+(?:my\s+)?(?:pw|password|pass)/i,
      /(?:i\s+)?(?:can'?t|cant|cannot)\s+(?:log\s*in|login|sign\s*in)/i,
      /(?:my\s+)?(?:pw|password|pass)\s+(?:isn'?t|isnt|not)\s+working/i,
      /(?:my\s+)?(?:pw|password|pass)\s+(?:doesn'?t|doesnt|don'?t|dont)\s+work/i,
      /need\s+(?:a\s+)?(?:new\s+)?(?:pw|password|pass)/i
    ].freeze

    # Bug 2/3/4 fix — May 19 2026:
    #   - Old regex #1 allowed "?" as trailing punctuation. Removed.
    #     Question-form is handled by QUESTION_GUARD below.
    #   - Old regex #2 had a bare `use\s+...` group that matched "I don't
    #     want to use cashapp". The `use ` literal is removed; negation form
    #     is handled by NEGATION_GUARD below. "I'll use cashapp" still
    #     matches via the `i'?ll\s+` prefix.
    #   - Old regex #3 ("do you have / got / have X") removed entirely —
    #     it's nearly always a question, not a pick. Edge case "got
    #     cashapp" alone is rare and customers rephrase.
    #   - New regex #3 catches "send me your X tag / X handle / X info" —
    #     a request FOR the handle, which is a clear pick.
    PAYMENT_METHOD_PICK_PATTERNS = [
      /\A\s*(cashapp|cash\s*app|chime|venmo|paypal|zelle)\s*[!.]*\s*\z/i,
      /(?:i'?ll\s+|i\s+wanna\s+|i\s+want\s+to\s+|let'?s\s+(?:do\s+)?|try\s+|gimme\s+|with\s+|do\s+|i\s+got\s+)(?:the\s+)?(cashapp|cash\s*app|chime|venmo|paypal|zelle)/i,
      /(?:send\s+(?:me\s+)?(?:your\s+|the\s+|a\s+|me\s+)?|gimme\s+(?:your\s+)?|pay\s+(?:via\s+|using\s+|on\s+|with\s+))(?:the\s+)?(cashapp|cash\s*app|chime|venmo|paypal|zelle)\s*(?:tag|handle|info|link|address|id)?/i,
      # "i'll use paypal" / "i wanna use cashapp" / "let's go with venmo" — lead-in + an
      # OPTIONAL verb + platform (PICK idx1 above needs the platform immediately, so a
      # verb broke it). Reached only AFTER the negation/question guards, so it never
      # overrides "i don't want to use cashapp" or a real question.
      /(?:i'?ll|i\s+wanna|i\s+want\s+to|let'?s|gonna|imma)\s+(?:use\s+|do\s+|go\s+with\s+|pay\s+(?:with|via)\s+)?(?:the\s+)?(cashapp|cash\s*app|chime|venmo|paypal|zelle)/i
    ].freeze

    # Tag/handle requests + bare-platform questions ("chime tag", "cash tag", "PayPal?",
    # "do you have apple pay") — asks for OUR handle / what we accept. Group 1 captures
    # the platform for downstream normalization. Checked alongside the PICK patterns.
    PAYMENT_TAG_REQUEST_PATTERNS = [
      /\b(chime|cashapp|cash\s*app|cash|venmo|paypal|zelle)\s+(?:tag|handle|info|address)\b/i,
      /\A\s*(cashapp|cash\s*app|chime|venmo|paypal|zelle)\s*\?+\s*\z/i,
      /\bdo\s+(?:you|u|yall|y'?all)\s+(?:have|take|accept|do)\s+(apple\s*pay|cashapp|cash\s*app|chime|venmo|paypal|zelle)/i
    ].freeze

    # Stand-downs: mentions a platform/handle but is NOT a method pick — cashout
    # request-direction, the customer's OWN $/@/+ handle, or a load question.
    PAYMENT_PICK_STANDDOWN_PATTERNS = [
      /\bwho\s+do\s+i\s+(?:send|request)/i,
      /\bsend\s+(?:the\s+)?request\b/i,
      /\brequest\s+\$?\d+\s+(?:to\s+)?(?:cashapp|cash\s*app|chime|venmo|paypal|zelle)/i,
      /\A\s*[$+@][a-z0-9][a-z0-9._\-]{2,}\s*\z/i,
      /\bwhere\s+do\s+i\s+(?:deposit|load|reload|put|add)\b/i,
      /\bhow\s+(?:do\s+i|u|to|can\s+i)\s+(?:load|deposit|reload)\b/i
    ].freeze

    # Bug 2 fix: if the customer's message ends with "?", treat it as a
    # question and DO NOT match payment_method_chosen. "you have only cash
    # app?" no longer fires the intent.
    PAYMENT_METHOD_QUESTION_GUARD = /\?\s*\z/

    # Bug 4 fix: if the customer's message contains a negation BEFORE a
    # platform name (within the same sentence, no '.', '!', or '?' between),
    # treat it as a rejection — NOT a pick. "I don't want to use cashapp"
    # no longer fires the intent.
    PAYMENT_METHOD_NEGATION_GUARD = /
      \b(?:don'?t|dont|do\s*not|won'?t|wont|will\s*not|never|no\s+thanks|nope|nah|not)\b
      [^.!?]*?
      (?:cashapp|cash\s*app|chime|venmo|paypal|zelle)
    /ix

    STATUS_CHECK_PATTERNS = [
      /any\s+update/i,
      /(?:did\s+(?:you|it)\s+)?go\s+through/i,
      /(?:has\s+it|did\s+it)\s+(?:been\s+)?(?:loaded|processed|gone\s+through)/i,
      /(?:what'?s?\s+)?(?:the\s+)?status/i,
      /(?:can\s+you\s+)?check\s+(?:on\s+it|if\s+it|that)/i,
      /(?:did\s+you|have\s+you)\s+(?:get|got|receive|received)\s+(?:it|my\s+(?:payment|money))/i,
      /(?:is\s+it|was\s+it)\s+(?:done|loaded|processed|complete)/i,
      /still\s+waiting/i,
      /how\s+long\s+(?:does|will|do)/i
    ].freeze

    COMPLAINT_ANGRY_PATTERNS = [
      /\b(?:wtf|wth|what\s+the\s+(?:fuck|hell|heck))\b/i,
      /\b(?:scam|fraud|fake|bullshit|bs)\b/i,
      /this\s+is\s+(?:ridiculous|unacceptable|a\s+scam)/i,
      /(?:i'?m\s+)?(?:so\s+)?(?:pissed|angry|mad|furious|frustrated)/i,
      /(?:you\s+guys?\s+)?(?:stole|robbing|stealing|cheating)\b/i,
      /(?:worst|terrible|horrible)\s+(?:service|support|experience)/i,
      /never\s+(?:again|using|coming\s+back)/i
    ].freeze

    TECH_ISSUE_PATTERNS = [
      /(?:game|app|it)\s+(?:is\s+)?not\s+(?:working|loading|opening)/i,
      /(?:can'?t|cannot|cant)\s+(?:open|load|access|get\s+into)\s+(?:the\s+)?(?:game|app)/i,
      /(?:game|app|server)\s+is\s+(?:down|offline|not\s+available)/i,
      /(?:stuck|frozen|crashing|crashed)\b/i,
      /(?:error|issue|problem)\s+(?:with|on)\s+(?:the\s+)?(?:game|app)/i,
      /(?:having\s+)?(?:trouble|issues?|problems?)\s+(?:logging|getting\s+in)/i
    ].freeze

    BALANCE_CHECK_PATTERNS = [
      /how\s+much\s+(?:do\s+i\s+have|is\s+(?:in\s+)?my\s+(?:account|balance))/i,
      /what'?s?\s+my\s+(?:balance|points?|credits?)/i,
      /what\s+is\s+my\s+(?:balance|points?|credits?)/i,
      /how\s+(?:much|many)\s+(?:do\s+i\s+have|points?|credits?|money)/i,
      /check\s+my\s+(?:balance|points?|credits?|account)/i,
      /how\s+many\s+(?:points?|credits?)\s+(?:do\s+i\s+have|are\s+left)/i,
      /\bnothing\s+(?:on|in|left)\b/i,
      /\bno\s+(?:money|balance|points?|credits?)\b/i,
      /\b(?:0|zero)\s+balance\b/i,
      /\bbalance\s+(?:is\s+)?(?:0|zero|empty)\b/i,
      /says?\s+i\s+(?:got|have)\s+(?:a\s+)?(?:0|zero|no)\b/i,
      /\bonly\s+\.?\d+\s*cents?\b/i,
      /\balmost\s+a\s+dollar\b/i,
      /what'?s?\s+my\s+max\b/i,
      /how\s+much\s+is\s+my\s+(?:cash\s*out|max)\b/i
    ].freeze

    # Balance REPORTS that include a number ("22 on there", "5 dollars on gv") — these
    # would otherwise be stolen by LOAD's broad number pattern. Checked BEFORE load via
    # balance_report? which ALSO vetoes any imperative load verb (load/add/put/etc).
    BALANCE_REPORT_PATTERNS = [
      /\b(?:i\s+(?:have|got)|i\s+still\s+(?:have|got)|theres?|there\s+is|only|just)\s+\$?\d+(?:\.\d{1,2})?\s*(?:dollars?|bucks?|cents?)?\s+(?:on|left|in)\b/i,
      /\b\$?\d+(?:\.\d{1,2})?\s*(?:dollars?|bucks?|cents?)\s+(?:on|left|in)\b/i,
      /\b\d+(?:\.\d{1,2})?\s+(?:on\s+there|left\s+(?:on|in)|still\s+(?:on|in|there))\b/i,
      /\bstill\s+(?:have|got)\s+\$?\d+/i
    ].freeze

    TRANSFER_PATTERNS = [
      /(?:transfer|move|switch|port)\s+(?:(?:my\s+)?(?:credits?|points?|balance|money)\s+)?(?:from\s+\w+\s+)?to\s+\w+/i,
      /(?:move|take)\s+(?:it|them|credits?|points?)\s+(?:from|off)\s+\w+\s+(?:to|onto)\s+\w+/i
    ].freeze

    WHATS_HITTING_PATTERNS = [
      /what\s+games?\s+(?:are\s+)?hitting/i,
      /what(?:'?s|\s+is)\s+(?:hitting|working|hot|good|available)/i,
      /which\s+games?\s+(?:are\s+)?(?:hitting|working|hot|good|available)/i,
      /any\s+(?:good\s+)?games?\s+(?:hitting|working|available)/i,
      /what\s+games?\s+(?:are\s+)?(?:up|on|running|live)/i,
      /what(?:'?s|\s+is)\s+(?:good|working)\s+(?:right\s+now|tonight|today)/i
    ].freeze

    REFERRAL_PATTERNS = [
      /i\s+(?:referred|sent)\s+(?:someone|a\s+friend|my\s+friend|them|him|her)/i,
      /(?:my|a)\s+referral/i,
      /(?:use|using|used)\s+my\s+(?:referral|code|link|ref)/i,
      /i\s+told\s+(?:them|him|her|my\s+friend)\s+(?:about|to\s+use)/i,
      /referral\s+(?:code|link|bonus|credit)/i,
      /(?:they|he|she)\s+(?:used|mentioned)\s+my\s+(?:name|referral)/i
    ].freeze

    def detect_sent_without_screenshot?(message_text)
      return false if message_text.blank?

      text = message_text.to_s.downcase
      sent_phrases = ['i sent', 'i paid', 'just sent', 'just paid', 'sent you', 'sent it',
                      'sent the money', 'sent the payment', 'money sent', 'payment sent',
                      'paid you', 'paid u', 'sent u']
      return false unless sent_phrases.any? { |p| text.include?(p) }
      return false if text.match?(/screenshot|receipt|proof|here'?s? (the )?pic/)

      true
    end

    class << self
      def detect(message_text)
        return nil if message_text.blank?

        text = message_text.to_s
        Rails.logger.info("[IntentDetector] checking text=#{text[0..200]}")

        return { intent: :greeting } if text.strip.match?(GREETING_PATTERNS) && text.strip.split.size <= 5

        # Status check before load/cashout — "any update on my load?" should not become :load
        if match_any(text, STATUS_CHECK_PATTERNS) && !match_any(text, LOAD_PATTERNS.first(6))
          Rails.logger.info('[IntentDetector] matched status_check (early)')
          return { intent: :status_check }
        end

        # Game-specific intents (load/cashout/reset) BEFORE payment_method_chosen so game
        # names like "Cash Machine" are not misread as a payment-platform pick.
        result = (if (multi_game = detect_multi_game(text))
                    multi_game
                  elsif (create_account = detect_account_creation_request(text))
                    create_account
                  elsif match_any(text, RESET_PASSWORD_PATTERNS)
                    Rails.logger.info('[IntentDetector] matched reset_password')
                    {
                      intent: :reset_password,
                      game_slug: detect_game(text),
                      game_username: extract_username(text)
                    }
                  elsif match_any(text, CASHOUT_RULES_PATTERNS)
                    Rails.logger.info('[IntentDetector] matched cashout_rules')
                    { intent: :cashout_rules, game_slug: detect_game(text) }
                  elsif (m = match_any(text, CASHOUT_PATTERNS))
                    Rails.logger.info("[IntentDetector] matched cashout amount=#{m[1]}")
                    {
                      intent: :cashout,
                      amount: m[1] ? m[1].to_f : nil,
                      game_username: extract_username(text),
                      game_slug: detect_game(text),
                      cashout_method: extract_cashout_method(text),
                      total_points: extract_points(text),
                      tip_amount: extract_tip(text),
                      reload_amount: extract_reload(text)
                    }
                  elsif match_any(text, FREEPLAY_PATTERNS)
                    amt = match_any(text, LOAD_PATTERNS)
                    Rails.logger.info('[IntentDetector] matched load_freeplay')
                    {
                      intent: :load_freeplay,
                      amount: amt && amt[1] ? amt[1].to_f : nil,
                      game_slug: detect_game(text)
                    }
                  elsif match_any(text, BONUS_PATTERNS)
                    amt = match_any(text, LOAD_PATTERNS)
                    Rails.logger.info('[IntentDetector] matched load_bonus')
                    {
                      intent: :load_bonus,
                      amount: amt && amt[1] ? amt[1].to_f : nil,
                      game_slug: detect_game(text)
                    }
                  elsif balance_report?(text)
                    Rails.logger.info('[IntentDetector] matched balance_check (report, pre-load)')
                    { intent: :balance_check, game_slug: detect_game(text) }
                  elsif (m = match_any(text, LOAD_PATTERNS))
                    amount = m[1] ? m[1].to_f : nil
                    # Some patterns capture username in group 2
                    captured_username = m[2] if m.size > 2 && m[2].present?
                    Rails.logger.info("[IntentDetector] matched load amount=#{m[1].inspect}")
                    {
                      intent: :load,
                      amount: amount,
                      game_username: captured_username || extract_username(text),
                      game_slug: detect_game(text)
                    }
                  elsif (new_acct = detect_new_account_request_with_game(text))
                    new_acct
                  elsif (m = match_payment_method_pick(text))
                    raw_platform = m[1].to_s.downcase.gsub(/\s+/, '')
                    normalized = %w[cash cashapp].include?(raw_platform) ? 'cashapp' : raw_platform
                    Rails.logger.info("[IntentDetector] matched payment_method_chosen platform=#{normalized}")
                    {
                      intent: :payment_method_chosen,
                      platform: normalized
                    }
                  elsif new.detect_sent_without_screenshot?(text)
                    Rails.logger.info('[IntentDetector] matched payment_sent_confirmation')
                    { intent: :payment_sent_confirmation }
                  elsif match_any(text, COMPLAINT_ANGRY_PATTERNS)
                    Rails.logger.info('[IntentDetector] matched complaint_angry')
                    { intent: :complaint_angry }
                  elsif match_any(text, TECH_ISSUE_PATTERNS)
                    Rails.logger.info('[IntentDetector] matched tech_issue')
                    { intent: :tech_issue }
                  elsif match_any(text, BALANCE_CHECK_PATTERNS)
                    Rails.logger.info('[IntentDetector] matched balance_check')
                    { intent: :balance_check, game_slug: detect_game(text) }
                  elsif match_any(text, TRANSFER_PATTERNS)
                    Rails.logger.info('[IntentDetector] matched transfer_between_games')
                    { intent: :transfer_between_games, game_slug: detect_game(text) }
                  elsif match_any(text, WHATS_HITTING_PATTERNS)
                    Rails.logger.info('[IntentDetector] matched whats_hitting')
                    { intent: :whats_hitting }
                  elsif match_any(text, REFERRAL_PATTERNS)
                    Rails.logger.info('[IntentDetector] matched referral')
                    { intent: :referral }
                  elsif match_any(text, PAYMENT_METHOD_QUESTION_PATTERNS)
                    Rails.logger.info('[IntentDetector] matched payment_method_question')
                    { intent: :payment_method_question }
                  elsif match_any(text, REQUEST_DOWNLOAD_LINK_PATTERNS)
                    Rails.logger.info('[IntentDetector] matched request_download_link')
                    { intent: :request_download_link, game_slug: detect_game(text) }
                  elsif match_any(text, REQUEST_APP_LINK_PATTERNS)
                    Rails.logger.info('[IntentDetector] matched request_app_link')
                    { intent: :request_app_link, game_slug: detect_game(text) }
                  elsif match_any(text, REQUEST_GAME_LINK_PATTERNS)
                    Rails.logger.info('[IntentDetector] matched request_game_link')
                    { intent: :request_game_link, game_slug: detect_game(text) }
                  elsif match_any(text, LIST_PLATFORMS_PATTERNS)
                    Rails.logger.info('[IntentDetector] matched list_platforms')
                    { intent: :list_platforms, game_slug: detect_game(text) }
                  elsif (username = extract_username(text)) && username.length >= 3
                    Rails.logger.info("[IntentDetector] matched username #{username}")
                    { intent: :username_provided, game_username: username, game_slug: detect_game(text) }
                  end)

        Rails.logger.info("[IntentDetector] result=#{result.inspect}")
        result
      end

      def detect_game(text)
        return nil if text.blank?
        resolved_slug = resolve_game_slug(text)
        return resolved_slug if resolved_slug.present?

        lower = text.to_s.downcase
        matches = []
        GAME_KEYWORDS.each do |slug, keywords|
          keywords.each do |kw|
            matches << [slug, kw] if lower.include?(kw)
          end
        end
        return nil if matches.empty?

        matches.max_by { |(_, kw)| kw.length }.first
      end

      def resolve_game_slug(text)
        return nil if text.nil? || text.to_s.strip.empty?

        normalized = text.to_s.downcase.strip
        GAME_NAME_ALIASES.keys.sort_by { |k| -k.length }.each do |alias_name|
          pattern = alias_name.split(/\s+/).map { |part| Regexp.escape(part) }.join('\s+')
          return GAME_NAME_ALIASES[alias_name] if normalized.match?(/\b#{pattern}\b/)
        end
        nil
      end

      private

      def detect_multi_game(text)
        return nil if text.blank?
        return nil unless match_any(text, CREATE_ACCOUNT_PATTERNS)

        lower = text.to_s.downcase
        if lower.match?(/\b(all|every|each)\s*(game|account|platform)s?\b/)
          return { intent: :request_multi_account_creation, game_slugs: :all }
        end

        slugs = []
        GAME_NAME_ALIASES.keys.sort_by { |k| -k.length }.each do |alias_name|
          pattern = alias_name.split(/\s+/).map { |part| Regexp.escape(part) }.join('\s+')
          slugs << GAME_NAME_ALIASES[alias_name] if lower.match?(/\b#{pattern}\b/)
        end
        slugs.uniq!

        return nil if slugs.size < 2

        { intent: :request_multi_account_creation, game_slugs: slugs }
      end

      def detect_account_creation_request(text)
        begin
          return nil if text.blank?
          return nil unless match_any(text, CREATE_ACCOUNT_PATTERNS)

          slug = detect_game(text)
          Rails.logger.info("[IntentDetector] matched request_account_creation slug=#{slug.inspect}")
          { intent: :request_account_creation, game_slug: slug.presence }
        rescue StandardError => e
          Rails.logger.warn("[IntentDetector] detect_account_creation_request failed: #{e.class}: #{e.message}")
          nil
        end
      end

      # "i need a juwa account" and similar — requires a known game from GAME_KEYWORDS; skips if a
      # probable username token is present so :username_provided can win on combined/latest text.
      def detect_new_account_request_with_game(text)
        begin
          return nil if text.blank?

          slug = resolve_game_slug(text)
          return nil if contains_probable_username_token?(text)
          return nil unless new_account_for_game_phrase?(text)

          Rails.logger.info("[IntentDetector] matched new_account_request_for_game slug=#{slug}")
          { intent: :request_account_creation, game_slug: slug }
        rescue StandardError => e
          Rails.logger.warn("[IntentDetector] detect_new_account_request_with_game failed: #{e.class}: #{e.message}")
          nil
        end
      end

      def game_name_regex_fragment
        @game_name_regex_fragment ||= begin
          keywords = GAME_NAME_ALIASES.keys.sort_by { |k| -k.length }
          keywords.map do |k|
            k.split(/\s+/).map { |part| Regexp.escape(part) }.join('\s+')
          end.join('|')
        end
      end

      def new_account_for_game_phrase?(text)
        norm = text.to_s.downcase.gsub(/\s+/, ' ').strip
        g = game_name_regex_fragment
        patterns = [
          /\bi\s+need\s+a\s+(?:#{g})\s+account\b/,
          /\bi\s+need\s+(?:#{g})\s+account\b/,
          /\bneed\s+a\s+(?:#{g})\s+account\b/,
          /\bneed\s+(?:#{g})\s+account\b/,
          /\bcan\s+i\s+get\s+a\s+(?:#{g})\s+account\b/,
          /\bcan\s+i\s+get\s+(?:#{g})\s+account\b/,
          /\bgive\s+me\s+a\s+(?:#{g})\s+account\b/,
          /\bgive\s+me\s+(?:#{g})\s+account\b/,
          /\bi\s+want\s+a\s+(?:#{g})\s+account\b/,
          /\bi\s+want\s+(?:#{g})\s+account\b/,
          /\bsign\s+me\s+up\s+for\s+(?:#{g})\b/,
          /\bset\s+me\s+up\s+on\s+(?:#{g})\b/,
          /\bcreate\s+a\s+(?:#{g})\s+account\b/,
          /\bmake\s+me\s+a\s+(?:#{g})\s+account\b/,
          /\bnew\s+(?:#{g})\s+account\b/
        ]
        patterns.any? { |p| norm.match?(p) }
      end

      def game_related_token?(tok)
        GAME_KEYWORDS.values.flatten.any? do |kw|
          kw == tok || kw.split(/\s+/).include?(tok)
        end
      end

      def contains_probable_username_token?(text)
        return true if extract_username(text).present?

        lower = text.to_s.downcase
        lower.scan(/\b[a-z0-9_]{4,}\b/).any? do |tok|
          next false if common_word?(tok)
          next false if game_related_token?(tok)

          tok.match?(/\d/)
        end
      end

      # Bug 2/3/4 fix: applies QUESTION and NEGATION guards before running
      # the pick patterns. A question or a negation about a platform is
      # NEVER a pick.
      def match_payment_method_pick(text)
        # Relaxed question-guard: a BARE platform question ("PayPal?", "Chime?") is an
        # ask for our handle, so it's allowed through; longer questions ("you only have
        # cashapp?") still bail via the unchanged guard.
        bare_platform_q = text.match?(/\A\s*(?:cashapp|cash\s*app|chime|venmo|paypal|zelle)\s*\?+\s*\z/i)
        return nil if !bare_platform_q && text =~ PAYMENT_METHOD_QUESTION_GUARD
        return nil if text =~ PAYMENT_METHOD_NEGATION_GUARD
        # Game name in message (e.g. Cash Machine) — not a payment-platform pick
        return nil if resolve_game_slug(text).present?
        # Request-direction / own-handle / load-question — not a pick.
        return nil if payment_pick_standdown?(text)

        match_any(text, PAYMENT_METHOD_PICK_PATTERNS + PAYMENT_TAG_REQUEST_PATTERNS)
      end

      def payment_pick_standdown?(text)
        PAYMENT_PICK_STANDDOWN_PATTERNS.any? { |re| text.match?(re) }
      end

      # True only for clear balance REPORTS; vetoes any imperative load verb so that
      # "load 22 on juwa" / "add 20" / "put 5 on gv" still route to :load.
      def balance_report?(text)
        return false if text.match?(/\b(?:load|add|recharge|top\s*up|deposit|put)\b/i)
        match_any(text, BALANCE_REPORT_PATTERNS) ? true : false
      end

      def match_any(text, patterns)
        patterns.each do |pattern|
          m = text.match(pattern)
          return m if m
        end
        nil
      end

      def extract_username(text)
        USERNAME_PATTERNS.each do |pattern|
          m = text.match(pattern)
          return m[1].downcase if m && m[1] && !common_word?(m[1])
        end
        nil
      end

      def extract_points(text)
        m = match_any(text, POINTS_PATTERNS)
        m && m[1] ? m[1].to_f : nil
      end

      def extract_tip(text)
        m = match_any(text, TIP_PATTERNS)
        m && m[1] ? m[1].to_f : nil
      end

      def extract_reload(text)
        m = match_any(text, RELOAD_PATTERNS)
        m && m[1] ? m[1].to_f : nil
      end

      def extract_cashout_method(text)
        CASHOUT_METHOD_PATTERNS.each do |pattern|
          m = text.match(pattern)
          next unless m && m[1].present?
          handle = m[1].to_s.strip
          platform = if text.downcase.include?('cashapp') || text.downcase.include?('cash app')
                       'cashapp'
                     elsif text.downcase.include?('chime')
                       'chime'
                     elsif text.downcase.include?('venmo')
                       'venmo'
                     elsif text.downcase.include?('paypal')
                       'paypal'
                     elsif text.downcase.include?('zelle')
                       'zelle'
                     else
                       'unknown'
                     end
          return { platform: platform, handle: handle }
        end
        nil
      end

      def common_word?(word)
        reserved = %w[
          load loaded cashout redeem deposit yes no please thanks thx help me you my the and but with from for now today
          game games vault gv orion juwa kirin fire milky way panda sweep vegas cash dragon lightning noble joker room cashier bella patra
          new old username user account password email phone number name
          ans send setup create need want first after that will check lyk did it hey can you
          fast slow good bad quick just also
        ]
        reserved.include?(word.downcase)
      end
    end
  end
end
