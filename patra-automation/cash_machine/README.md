# Gameroom automation

Phase 1 supports login only.

Gameroom is not an ASP.NET WebForms panel like Milky Way, Fire Kirin, Panda Master, or Orion Stars. It uses layui with a Go backend, a canvas-rendered CAPTCHA, and layui-layer popups. This driver keeps the shared Patra automation structure for AdsPower, Telegram CAPTCHA solving, argparse commands, and JSON output, but the page logic is written specifically for Gameroom.

## Setup

1. Fill `GAMEROOM_PASS` in `.env`.
2. Use the existing Python environment, or create a fresh one:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
py -3.12 -m playwright install chromium
```

## Login

```powershell
py -3.12 gameroom.py login
```

Expected flow:

- AdsPower starts or reuses profile `k1clailr`.
- Browser navigates to `https://agentserver.gameroom777.com/admin/login`.
- `canvas#verifyCanvas` is captured and posted to the Telegram CAPTCHA group.
- Reply with the 4-character CAPTCHA code.
- On success, the script reaches the dashboard and prints `{"status":"success","action":"login"}`.

## Phase 2

The CLI already exposes `balance`, `recharge`, `redeem`, `create`, and `reset`, but those commands currently return `NOT_IMPLEMENTED`. Phase 2 will add the dashboard/player-table iframe work for those actions once login is verified.
