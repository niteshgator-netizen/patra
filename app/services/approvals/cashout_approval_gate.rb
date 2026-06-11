# frozen_string_literal: true

module Approvals
  class CashoutApprovalGate
    DEFAULT_THRESHOLD = 500

    def self.requires_approval?(account, amount)
      threshold = (account.custom_attributes || {}).stringify_keys['cashout_approval_threshold'].to_f
      threshold = DEFAULT_THRESHOLD if threshold <= 0
      amount.to_f > threshold
    end

    def self.create_request!(account:, user:, amount:, target:, metadata: {})
      # user can be nil in Sidekiq (Current.user unset) on an account with no
      # account_users; requesting_user is a required association, so create!
      # would raise OUT of cashout_player and the over-threshold cashout would
      # crash instead of being held. Fail CLOSED: skip the row, still alert,
      # caller still returns ok:false / approval_required.
      request = nil
      if user
        request = ApprovalRequest.create!(
          account: account,
          requesting_user: user,
          action_type: 'cashout',
          target_type: target.class.name,
          target_id: target.id,
          amount: amount,
          status: 'pending',
          metadata: metadata
        )
      else
        Rails.logger.error("[CashoutApprovalGate] no requesting user (account #{account.id}) — approval row skipped, cashout stays HELD")
      end

      player = metadata[:player_name] || metadata['player_name'] || 'player'
      game = metadata[:game_name] || metadata['game_name'] || 'game'
      agent = user&.name || 'system'

      Audit::TelegramNotifier.approval_needed(
        account: account,
        text: "🔒 Approval needed: $#{amount} cashout for #{player} on #{game} by #{agent}. Reply /approve or /reject"
      )

      request
    end
  end
end
