# Milky Way automation (Patra)

Controls an AdsPower-protected Chrome browser via Playwright to automate Milky Way agent panel actions: login, search, recharge, redeem, create player, reset password, read balance.

## One-time setup

1. Install Python 3.11+ if you don't have it.
2. From PowerShell in this folder:
   ```powershell
   py -3.12 -m pip install -r requirements.txt
   py -3.12 -m playwright install chromium
   ```
3. Copy `.env.example` to `.env` and fill in:
   - `MILKY_WAY_PASS` — your hamro555D password
   - `TELEGRAM_BOT_TOKEN` — `8878122491:AAG41As6M2VcwBxg9ZLIHVloM4Tlu0fn5II` (already in Railway)
4. Open the AdsPower app (the launcher must be running for the Local API at port 50325 to work).

## Run

```powershell
# One-time per day: open AdsPower app and run login (solves 1 CAPTCHA)
py -3.12 milky_way.py login

# Then all subsequent commands reuse the running browser — no CAPTCHA, ~2s each
py -3.12 milky_way.py balance  --player kara123_mw
py -3.12 milky_way.py recharge --player kara123_mw --amount 1
py -3.12 milky_way.py redeem   --player kara123_mw --amount 1
py -3.12 milky_way.py create   --account newuser1   --password test12345
py -3.12 milky_way.py reset    --player kara123_mw  --password newpass456
```

End-of-day: just close AdsPower normally. Override by setting ADSPOWER_KEEP_OPEN=0 in .env.

Each command prints ONE JSON line and exits 0 (success) or 1 (failure). Failures include a `screenshot` path you can open to see what the browser saw.

## How it works (plain English)

- AdsPower's Local API tells our code where its Chrome browser is running (a WebSocket URL).
- Playwright connects to that running Chrome over that WebSocket — no new browser is launched.
- The script navigates Milky Way, fills forms, clicks buttons, just like a human.
- When CAPTCHA appears, the script screenshots the CAPTCHA image, sends it to a Telegram group, and waits for any human in the group to reply with the digits.
- After a redeem, a summary is sent to the cashout Telegram group.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `AdsPower start failed` | AdsPower app not running |
| `MISSING_ENV` | `.env` not filled in |
| `CAPTCHA_TIMEOUT` | No one in the captcha group replied in 90s |
| `LOGIN_FAILED` | Wrong creds, or CAPTCHA replied wrong 3× — open the `error_*.png` |
| `PLAYER_NOT_FOUND` | Account typo, or player is in the prohibited list |
| `PAGE_TIMEOUT` | Milky Way slow/down, or selector changed — open the screenshot |
