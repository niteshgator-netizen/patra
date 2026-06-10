# PROPOSED MIGRATION — DO NOT RUN AUTOMATICALLY (launch-night policy: no db/migrate files).
# Copy into db/migrate/ with a fresh timestamp after review, deploy via Render.
#
# WHY: the money fraud guards all filter game_actions by the same column combo:
#   - ConversationOrchestrator#cashout_velocity_state:
#       WHERE account_id=? AND contact_id=? AND action_type='cashout' AND status='success' AND created_at >= ?
#   - #recent_cashout_duplicate?:
#       WHERE account_id=? AND contact_id=? AND agent_game_id=? AND action_type='cashout' AND status IN (...) AND amount=? AND created_at >= ?
#   - #duplicate_recent_load? and GameAction.loaded_today_for_contact:
#       WHERE account_id=? AND contact_id=? AND action_type='load' AND status='success' [AND amount=?] AND created_at >= ?
#   - #original_deposit_on_source: contact_id + action_type + status ordered by created_at DESC
#
# Existing indexes: [account_id, order_id] (unique), [account_id, action_type, created_at],
# [contact_id], [conversation_id], [game_username]. None covers the contact-scoped guard
# pattern; today Postgres bitmap-ANDs [contact_id] with the others. Fine at current volume,
# but these guards sit on the hot money path and run on EVERY load/cashout/transfer turn.
#
# These queries currently return in single-digit ms at ~10k rows; this becomes important
# past ~100k+ game_actions. Low urgency, high safety (pure additive index).

class AddGameActionsMoneyGuardIndex < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :game_actions,
              [:account_id, :contact_id, :action_type, :status, :created_at],
              name: 'idx_game_actions_money_guards',
              algorithm: :concurrently
  end
end
