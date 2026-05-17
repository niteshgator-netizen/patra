# Bugs Crushed — Milky Way Build (2026-05-16)

Reference doc for replicating this automation to other game panels. Every bug here cost real debugging time — read before building the next one.

## Stack confirmed working
- AdsPower Local API V2 (paid plan, Professional 10 profiles, $86/yr annual)
- Playwright sync API + chromium connect_over_cdp
- Python 3.12 (NOT 3.14 — playwright wheels don't exist for 3.14)
- Windows PowerShell, `py -3.12` launcher
- Telegram bot for human-in-the-loop CAPTCHA solving

## Bug log (chronological, with fix)

1. **AdsPower API auth changed.** Free-plan API now requires auth. Header must be `Authorization: Bearer <key>` — NOT `api-key: <key>` (which the older docs and ChatGPT suggest). Use the official docs https://localapi-doc-en.adspower.com/docs/Rdw7Iu for the current header name.

2. **AdsPower free plan daily-open limit.** Free plan caps browser opens per day. Burns fast during debug iterations. Fix: upgrade to Professional ($86/yr annual) OR use the `adspower_status` reuse pattern (see milky_way.py `adspower_status` function).

3. **Dialog iframe location.** I assumed action dialogs (Recharge, Redeem, Reset, Create) opened inside the main `frm_main_content` iframe. They actually open at the TOP page level inside `div#DialogBySHF iframe`. Selector: `page.frame_locator("div#DialogBySHF iframe")` — NOT `main_frame.frame_locator(...)`.

4. **mb_box overlay sticks.** Milky Way's `<div id="mb_box">` (dark backdrop for popups) does NOT auto-remove after dismissal. Intercepts ALL clicks indefinitely. Fix: force-clear via JS that does `el.remove()` for `DialogBySHF`/`DialogBySHFLayer` and `display:none + innerHTML=''` for `mb_box`/`mb_con`/`msgBoxDIV`. Call before every action click.

5. **Error popup blocks login retries.** When CAPTCHA is wrong, Milky Way shows a "validation code incorrect" popup that must be dismissed before retrying. Default Playwright click loop silently fails 2nd and 3rd attempts. Fix: dismiss any leftover `mb_con` OK button at the START of every login attempt.

6. **Success popup location is the dialog iframe, not the page.** `wait_for_success_popup()` must check three places: top page, main iframe, AND dialog iframe.

7. **Duplicate dialog on retry.** After insufficient-funds error, calling Milky Way's `closeDialog()` only hides — doesn't remove. Retry creates a SECOND `DialogBySHF` iframe. Playwright errors with "strict mode violation: resolved to 2 elements". Fix: `el.remove()` on `DialogBySHF` before retrying.

8. **Amount field clearing is hard.** Input has `onkeyup="this.value=this.value.replace(/\D/g,'')"` (strips non-digits). Playwright's `.fill("")` doesn't fire keyup. `.press("Control+a")` selects but `.type()` then INSERTS at cursor. `.press_sequentially()` types next to existing value. Fix: set `el.value = ''` via JS + dispatch input event, then `press_sequentially`. Verify with `input_value()`.

9. **Milky Way accepts whole dollars only.** `--amount 1.0` becomes `10` (the dot gets stripped by onkeyup). Coerce float→int and reject non-whole amounts with clear error message.

10. **ASP.NET ViewState fragility.** `force=True` + `no_wait_after=True` clicks bypass Playwright's wait-for-stability checks AND skip post-click navigation handling. ASP.NET postbacks need both. Result: "Server Error in '/' Application" Runtime Error. Fix: use normal `.click()` with normal timeouts. Slower but works.

## Architecture patterns to copy

- **All Telegram calls wrapped in `@safe_telegram` decorator.** Telegram outages must NEVER kill a recharge.
- **CAPTCHA queue:** snapshot `update_id` BEFORE posting photo. Otherwise stale messages match.
- **Top-up retry:** 3 attempts max, 30-min Telegram timeout per attempt, distinct error code `AGENT_FUNDS_EXHAUSTED` for Bella to pattern-match.
- **JSON output on stdout, logs on stderr.** Lets Rails parse cleanly via subprocess.
- **Screenshot on every failure.** Saves to `error_<command>_<timestamp>.png`. Indispensable when debugging at 1am.
- **Persistent browser (`ADSPOWER_KEEP_OPEN=1`)** is the only way per-command latency stays acceptable. Open once daily.

## Estimated effort for next game

Web panel game (similar to Milky Way): 2-3 hours WITH this template.
Telegram-bot game (Orion Stars, Fire Kirin, Gameroom): different code entirely — uses Telegram Bot API, not AdsPower. Build in Month 2 per roadmap.
