# Proposed migrations (launch-night TAB B)

Policy: TAB B writes **no** files in `db/migrate/` and runs **no** migrations.
Anything here is a reviewed-and-ready proposal — copy into `db/migrate/` with a
fresh timestamp when you choose to apply it.

## Index audit summary (2026-06-10)

NOTE: `db/schema.rb` is STALE — it predates every Patra table. The audit below
was done directly against the `db/migrate/*.rb` files (source of truth that
Render deploys actually run).

| Table | Existing indexes | Verdict |
|---|---|---|
| games | slug (uniq), status, sort_order | OK |
| agent_games | [account,game] uniq, [account,status], game_id | OK |
| game_actions | [account,order_id] uniq, [account,action_type,created_at], contact_id, conversation_id, game_username | GAP → `20260610_add_game_actions_money_guard_index.rb` (contact-scoped fraud-guard combo) |
| player_bonuses | account, contact, [account,contact], given_by_user | OK |
| holidays | account, inbox, [account,closed_on] | OK |
| cashier_claims | account, conversation, contact, [account,status], expires_at | OK |
| backup_pages | account, [account,status], [account,position] | OK |
| game_rules | account, game, [account,game] uniq | OK |
| player_tiers | account, [account,name] uniq, contacts.player_tier_id | OK |
| referrals | account, referrer_contact, referred_contact, [account,referrer_contact] | OK |
| reply_preferences | account_id uniq | OK |
| payment_handles | [account,platform,priority], [account,platform,status] | OK |

Also recommended (operator task, not a migration): regenerate `db/schema.rb`
(`bundle exec rails db:schema:dump` against a migrated DB) so future audits and
new-environment setups don't read a pre-Patra schema.
