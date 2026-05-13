# Parses cashout/bonus rules from the operator's ai_training canned responses
# and calculates the right cashout amount + remaining points.

module Games
  class CashoutCalculator
    DEFAULT_MIN_PLAYTHROUGH = 4
    DEFAULT_MAX_PLAYTHROUGH = 10

    Result = Struct.new(:cashout_amount, :remaining_points, :min_required, :max_allowed, :applied_rules, :explanation, keyword_init: true)

    attr_reader :account, :deposit_amount, :requested_amount, :total_points

    def initialize(account:, deposit_amount:, requested_amount:, total_points: nil)
      @account = account
      @deposit_amount = deposit_amount.to_f
      @requested_amount = requested_amount.to_f
      @total_points = (total_points || requested_amount).to_f
    end

    def calculate
      rules = parse_rules_from_training
      min_required, max_allowed = playthrough_range(rules)

      min_dollar = (deposit_amount * min_required).round(2)
      max_dollar = (deposit_amount * max_allowed).round(2)

      explanation = []
      applied = []

      # If player hasn't met minimum playthrough, reject
      if total_points < min_dollar
        explanation << "Player needs #{min_required}x playthrough on $#{deposit_amount} deposit (= $#{min_dollar} minimum) to cashout. Currently at $#{total_points}."
        return Result.new(cashout_amount: 0, remaining_points: total_points, min_required: min_dollar, max_allowed: max_dollar, applied_rules: applied, explanation: explanation.join(' '))
      end

      # Cap the cashout at max playthrough
      cashout = [requested_amount, max_dollar, total_points].min
      remaining = (total_points - cashout).round(2)

      applied << "#{max_allowed}x max playthrough on $#{deposit_amount} deposit = $#{max_dollar} cap"
      if requested_amount > max_dollar
        explanation << "Player requested $#{requested_amount} but max cashout is $#{max_dollar} (#{max_allowed}x of $#{deposit_amount} deposit). Paying $#{cashout}, $#{remaining} stays in game."
      else
        explanation << "Cashout of $#{cashout} approved. $#{remaining} remaining in game."
      end

      Result.new(
        cashout_amount: cashout,
        remaining_points: remaining,
        min_required: min_dollar,
        max_allowed: max_dollar,
        applied_rules: applied,
        explanation: explanation.join(' ')
      )
    end

    private

    def parse_rules_from_training
      # Returns the raw canned response text for cashout rules
      # Patra's existing pattern uses CannedResponse model
      texts = []
      if defined?(CannedResponse)
        CannedResponse.where(account_id: account.id).find_each do |cr|
          content = "#{cr.short_code} #{cr.content}".downcase
          texts << content if content.include?('cashout') || content.include?('playthrough') || content.include?('redeem')
        end
      end
      texts.join("\n")
    end

    def playthrough_range(rules_text)
      # Try to extract min and max playthrough from the rules text
      # Looking for patterns like "min 4x" and "max 10x"
      min_match = rules_text.match(/min\s+(\d+)x/i)
      max_match = rules_text.match(/max\s+(\d+)x/i)

      min = min_match ? min_match[1].to_i : DEFAULT_MIN_PLAYTHROUGH
      max = max_match ? max_match[1].to_i : DEFAULT_MAX_PLAYTHROUGH

      # Different rules for <$5 vs >$5 deposits (from Patra's existing rules)
      if deposit_amount < 5
        max_below_5 = rules_text.match(/<\s*\$?5.*?max\s+(\d+)x/im)
        max = max_below_5[1].to_i if max_below_5
      end

      [min, max]
    end
  end
end
