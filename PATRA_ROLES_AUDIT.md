# PATRA ROLES & AUTHORIZATION AUDIT — TAB A (2026-06-10 overnight, AUDIT-ONLY)

NOTHING ENFORCED TONIGHT (by design: restricting money endpoints with nobody awake risks
locking the owner out mid-launch). All findings (a) read-verified; the critical one
(agent_games money endpoints) re-verified directly by TAB A, not just sub-agent output.

## Roles that exist today
- Chatwoot stock: `agent` / `administrator` (account_user.rb:34 enum).
- Enterprise CustomRole: 6 conversation/contact/report/KB permissions (enterprise custom_role.rb:31-38) — none cover games or money.
- There is NO cashier/viewer/employee/owner role concept anywhere in code (grepped models/policies/controllers).
  "Owner" today simply = administrator. "Cashier/employee" = agent.

## What each role CAN do today (money-relevant)
| Capability | agent | administrator |
|---|---|---|
| Manual load via API (agent_games#load_player) | **YES** (no guard — verified: agent_games_controller.rb:1-2 only has fetch_agent_game) | YES |
| Manual cashout via API (#cashout_player) | **YES** (no guard; >threshold still hits the approval gate, and per-game max caps apply in ActionExecutor) | YES |
| add_player / reset_player_password / test_connection | **YES** (no guard) | YES |
| Approve/reject cashout approvals | NO (approval_requests_controller.rb:4 check_admin_authorization?) | YES |
| Edit game rules / player tiers / reply preferences / referral records | **YES** (game_rules, player_tiers, reply_preferences, referrals#create/update have NO guard) | YES |
| Referral SETTINGS update | NO (referrals_controller.rb:7 admin-only on update_settings) | YES |
| Payment handle list | YES (PaymentHandlePolicy index allows agent) | YES |
| Payment handle create/update/delete/ledger | NO (policy admin-only) | YES |
| Patra business settings / FB connect / incident controls / holidays | NO (check_admin_authorization?) | YES |
| Patra dashboards/reports | NO (ReportPolicy admin-only), except patra/dashboard + leaderboard routes visible to agents | YES |
| Cashier claims (claim/complete a cashout task) | **YES** (cashier_claims_controller has no role guard) | YES |

## Exact gaps (priority order)
1. **agent_games_controller.rb — money actions unguarded.** load_player:73, cashout_player:101,
   add_player:146, reset_player_password:170. Mitigations that DO apply: account scoping
   (Current.account...), per-game max_load/max_cashout caps, blacklist check, >threshold
   cashout approval gate, full GameAction audit trail with operator_user_id stamped
   (metadata source 'manual_ui'). Still: any agent can move money under the caps.
2. **game_rules / player_tiers / reply_preferences controllers unguarded** — any agent can
   change bonus %, cashout multipliers, fraud-guard thresholds, or disable AI memory.
   Changing reply_preferences also flips money-adjacent behavior (confirm_before_cashout!).
3. **referrals#create/update unguarded** — any agent can mark referrals verified.
4. **cashier_claims unguarded** — acceptable if all agents ARE cashiers; flag for owner decision.
5. Frontend hides admin pages from agents (dashboard.routes.js meta.permissions) but that is
   navigation-only — direct API calls bypass it.

## HANDOFF-B-3 (controllers = TAB B lane; do NOT apply while operator sleeps)
Proposed minimal diff, gated behind ENV so it ships dark and the operator flips it after launch:
```ruby
# app/controllers/api/v1/accounts/agent_games_controller.rb
before_action :check_money_action_authorization, only: %i[load_player cashout_player add_player reset_player_password]

def check_money_action_authorization
  return unless ENV['PATRA_RESTRICT_MONEY_ACTIONS'].to_s == 'true'   # default OFF tonight
  check_admin_authorization?
end
```
Same pattern for game_rules/player_tiers/reply_preferences update actions (read can stay open).
Longer term: extend CustomRole with game_manage / money_operations permissions.

## Morning decision for Genius (1 minute)
If every human with dashboard access is trusted to move money: no action needed.
Otherwise have TAB B apply HANDOFF-B-3 and set PATRA_RESTRICT_MONEY_ACTIONS=true after
confirming your own user is administrator.
