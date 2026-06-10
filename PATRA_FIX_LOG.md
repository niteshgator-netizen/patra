# PATRA FINISHER RUN — FIX LOG

**ROLLBACK HASH (state before this run): `8e00f07196ec9c8256168c614e8e627b03d17049`**
Run date: 2026-06-10 · Branch: main · No pushes in this run.

---

## CI — GitHub Actions spec runner

- Created `.github/workflows/run_specs.yml` exactly as specified. No other workflow file touched.
- Verified all 23 spec paths in the rspec command exist on disk (Test-Path each one) — **zero removals needed**.
- YAML parse check: `ruby -ryaml -e "YAML.load_file('.github/workflows/run_specs.yml')"` → OK.
- Boot ENV audit: grepped `config/` and `spec/` for `ENV.fetch` without a default.
  - `config/puma.rb` (3 hits) — all use block fallbacks, safe.
  - `config/environments/production.rb` ASSET_CDN_HOST — guarded by `.present?` and production-only; test env never loads it.
  - `config/database.yml` test stanza — every key has a default (`chatwoot_test` / `postgres` / empty password), matches workflow env.
  - **No additional ENV vars added.**

## FIX1 — Inbox report 404

- **Root cause (verified by reading code):** `reports.routes.js` registers the inbox report at path `inboxes` (plural, route name `inbox_reports`), while Agent and Label use singular paths (`agent`, `label`). `/reports/inbox` (singular) matched nothing and fell through to the `not_found` catch-all in `dashboard.routes.js:135`.
- Grepped the entire `app/javascript` tree: **no nav link, sidebar item, or command anywhere points to singular `reports/inbox`** — the sidebar only links `patra_reports`; the command bar (useGoToCommandHotKeys.js) uses the working plural `reports/inboxes`. So the 404 comes from typed/bookmarked URLs, and there was no nav target to "correct".
- **Decision: register the missing singular route as a redirect** (`inbox` → named route `inbox_reports`), using the same redirect shape already used for the empty path in the same file. Additive only — the working plural URL and command-bar links are untouched. Did NOT rename `inboxes`→`inbox` because that would break the currently-working plural URL and the command-bar hotkey paths.
- Registration shape after fix: agent → `agent` ✓, label → `label` ✓, inbox → `inbox` (redirect) + `inboxes` ✓ — all singular paths now resolve.
- `pnpm exec vite build` → green (✓ built in 41.07s).

## FIX2 — Team report 404

- Checked components first: `TeamReports.vue`, `TeamReportsIndex.vue`, `TeamReportsShow.vue` all exist on disk and are already imported + registered in `reports.routes.js` (paths `teams`, `teams_overview`, `teams/:id`). So this is the same singular/plural mismatch as FIX1, NOT a missing-page case — no nav link removal needed.
- **Decision:** same additive redirect as FIX1 — registered `team` → named route `team_reports`. Plural `teams` URL and command-bar link untouched.
- `pnpm exec vite build` → green (✓ built in 37.28s).

## FIX3 — Blank profile page

(pending)
