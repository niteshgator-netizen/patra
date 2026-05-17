"""
Milky Way automation — controls AdsPower-protected Chrome via Playwright.

Usage (PowerShell):
    python milky_way.py login
    python milky_way.py recharge --player kara123_mw --amount 1
    python milky_way.py redeem   --player kara123_mw --amount 1
    python milky_way.py create   --account newuser1  --password mypass123
    python milky_way.py reset    --player kara123_mw --password newpass456
    python milky_way.py balance  --player kara123_mw

Every command prints a single JSON line to stdout and exits 0 (success) or 1 (failure).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import requests
from dotenv import load_dotenv
from playwright.sync_api import (
    sync_playwright,
    Page,
    FrameLocator,
    TimeoutError as PlaywrightTimeout,
)

# ─────────────────────────────────────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────────────────────────────────────
load_dotenv()

ADSPOWER_API = os.getenv("ADSPOWER_API", "http://127.0.0.1:50325")
ADSPOWER_PROFILE_ID = os.getenv("ADSPOWER_PROFILE_ID", "k1cl3kvv")
ADSPOWER_API_KEY = os.getenv("ADSPOWER_API_KEY", "")
ADSPOWER_KEEP_OPEN = os.getenv("ADSPOWER_KEEP_OPEN", "1") == "1"
ADSPOWER_REUSE_IF_OPEN = os.getenv("ADSPOWER_REUSE_IF_OPEN", "1") == "1"
MILKY_WAY_USER = os.getenv("MILKY_WAY_USER", "")
MILKY_WAY_PASS = os.getenv("MILKY_WAY_PASS", "")
MILKY_WAY_URL = os.getenv("MILKY_WAY_URL", "https://milkywayapp.xyz:8781")
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
CAPTCHA_GROUP_ID = os.getenv("CAPTCHA_GROUP_ID", "-5214874121")
CASHOUT_GROUP_ID = os.getenv("CASHOUT_GROUP_ID", "-5243223053")
TOPUP_ALERT_GROUP_ID = os.getenv("TOPUP_ALERT_GROUP_ID", CASHOUT_GROUP_ID)
TOPUP_TIMEOUT_SEC = int(os.getenv("TOPUP_TIMEOUT_SEC", "1800"))
TOPUP_MAX_RETRIES = int(os.getenv("TOPUP_MAX_RETRIES", "3"))
CAPTCHA_TIMEOUT_SEC = int(os.getenv("CAPTCHA_TIMEOUT_SEC", "90"))
LOGIN_MAX_RETRIES = int(os.getenv("LOGIN_MAX_RETRIES", "3"))


# ─────────────────────────────────────────────────────────────────────────────
# Output helpers — every script run ends with EXACTLY one JSON line on stdout.
# ─────────────────────────────────────────────────────────────────────────────
def emit(payload: dict) -> None:
    print(json.dumps(payload, separators=(",", ":")))


def fail(action: str, code: str, message: str, screenshot: str | None = None) -> None:
    out = {"status": "error", "action": action, "error_code": code, "error_message": message}
    if screenshot:
        out["screenshot"] = screenshot
    emit(out)
    sys.exit(1)


def log(msg: str) -> None:
    """Diagnostic — goes to stderr so it doesn't pollute the JSON on stdout."""
    print(f"[milky_way] {msg}", file=sys.stderr, flush=True)


# ─────────────────────────────────────────────────────────────────────────────
# AdsPower Local API
# ─────────────────────────────────────────────────────────────────────────────
def adspower_start(profile_id: str) -> str:
    """Start the profile browser, return the puppeteer WebSocket URL."""
    r = requests.get(
        f"{ADSPOWER_API}/api/v1/browser/start",
        params={"user_id": profile_id},
        headers={"Authorization": f"Bearer {ADSPOWER_API_KEY}"},
        timeout=30,
    )
    r.raise_for_status()
    data = r.json()
    if data.get("code") != 0:
        raise RuntimeError(f"AdsPower start failed: {data.get('msg')}")
    ws_url = data["data"]["ws"]["puppeteer"]
    log(f"AdsPower started, ws={ws_url}")
    return ws_url


def adspower_stop(profile_id: str) -> None:
    """Best-effort stop. Never raises."""
    try:
        requests.get(
            f"{ADSPOWER_API}/api/v1/browser/stop",
            params={"user_id": profile_id},
            headers={"Authorization": f"Bearer {ADSPOWER_API_KEY}"},
            timeout=10,
        )
        log("AdsPower stopped")
    except Exception as e:
        log(f"AdsPower stop ignored: {e}")


def adspower_status(profile_id: str) -> dict | None:
    """Check if the profile is already running. Returns the active ws URL if so, else None."""
    try:
        r = requests.get(
            f"{ADSPOWER_API}/api/v1/browser/active",
            params={"user_id": profile_id},
            headers={"Authorization": f"Bearer {ADSPOWER_API_KEY}"},
            timeout=10,
        )
        data = r.json()
        if data.get("code") != 0:
            return None
        d = data.get("data") or {}
        if d.get("status") == "Active" and d.get("ws", {}).get("puppeteer"):
            return d["ws"]["puppeteer"]
    except Exception as e:
        log(f"adspower_status check ignored: {e}")
    return None


# ─────────────────────────────────────────────────────────────────────────────
# Telegram — every call wrapped in safe_telegram. Failures are logged, never raised.
# ─────────────────────────────────────────────────────────────────────────────
def safe_telegram(fn):
    def wrapper(*args, **kwargs):
        try:
            return fn(*args, **kwargs)
        except Exception as e:
            log(f"telegram error in {fn.__name__}: {e}")
            return None
    return wrapper


@safe_telegram
def telegram_send_photo(chat_id: str, photo_bytes: bytes, caption: str) -> dict | None:
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendPhoto"
    files = {"photo": ("captcha.png", photo_bytes, "image/png")}
    data = {"chat_id": chat_id, "caption": caption}
    r = requests.post(url, files=files, data=data, timeout=30)
    return r.json()


@safe_telegram
def telegram_send_message(chat_id: str, text: str) -> dict | None:
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    r = requests.post(
        url,
        json={"chat_id": chat_id, "text": text, "parse_mode": "HTML"},
        timeout=30,
    )
    return r.json()


@safe_telegram
def telegram_get_updates(offset: int | None = None, timeout: int = 5) -> dict | None:
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/getUpdates"
    params: dict = {"timeout": timeout}
    if offset is not None:
        params["offset"] = offset
    r = requests.get(url, params=params, timeout=timeout + 10)
    return r.json()


def solve_captcha_via_telegram(image_bytes: bytes, request_id: str) -> str:
    """
    Post captcha to the captcha group, wait for the first digit-only reply.
    Returns the captured digits as a string. Raises TimeoutError on no-answer.
    """
    # Snapshot current update_id high-water-mark BEFORE posting, so we ignore stale msgs.
    initial = telegram_get_updates(timeout=0)
    last_id = 0
    if initial and initial.get("ok"):
        last_id = max((u["update_id"] for u in initial.get("result", [])), default=0)

    caption = (
        f"🔢 CAPTCHA needed — Milky Way login\n"
        f"Request: {request_id}\n"
        f"Reply with just the digits (3–8 numbers)."
    )
    telegram_send_photo(CAPTCHA_GROUP_ID, image_bytes, caption)
    log(f"Captcha posted to group {CAPTCHA_GROUP_ID}, request_id={request_id}")

    digit_re = re.compile(r"^\s*(\d{3,8})\s*$")
    start = time.time()
    offset = last_id + 1

    while time.time() - start < CAPTCHA_TIMEOUT_SEC:
        updates = telegram_get_updates(offset=offset, timeout=5)
        if not updates or not updates.get("ok"):
            time.sleep(1)
            continue
        for upd in updates.get("result", []):
            offset = upd["update_id"] + 1
            msg = upd.get("message") or upd.get("channel_post") or {}
            chat_id = str(msg.get("chat", {}).get("id", ""))
            if chat_id != str(CAPTCHA_GROUP_ID):
                continue
            text = msg.get("text", "")
            m = digit_re.match(text)
            if m:
                digits = m.group(1)
                log(f"Captcha solved: {digits}")
                return digits

    raise TimeoutError(f"CAPTCHA not solved within {CAPTCHA_TIMEOUT_SEC}s")


def send_cashout_report(
    account: str, amount: float, new_balance: float, agent_balance: float | None
) -> None:
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    agent_str = f"${agent_balance:.2f}" if agent_balance is not None else "?"
    text = (
        f"🟢 <b>REDEEM</b> | Milky Way\n"
        f"Player: <code>{account}</code>\n"
        f"Amount: ${amount:.2f}\n"
        f"New player balance: ${new_balance:.2f}\n"
        f"Agent balance: {agent_str}\n"
        f"Time: {ts} UTC"
    )
    telegram_send_message(CASHOUT_GROUP_ID, text)


def wait_for_topup_signal(player: str, amount: float) -> bool:
    """
    Post a 'agent funds needed' alert to TOPUP_ALERT_GROUP_ID, wait for any
    message containing 'loaded' (case-insensitive). Returns True on confirmation,
    False on timeout.
    """
    initial = telegram_get_updates(timeout=0)
    last_id = 0
    if initial and initial.get("ok"):
        last_id = max((u["update_id"] for u in initial.get("result", [])), default=0)

    alert = (
        f"⚠️ <b>AGENT FUNDS NEEDED</b> | Milky Way\n"
        f"Agent: <code>{MILKY_WAY_USER}</code>\n"
        f"Cannot recharge <code>{player}</code> for ${amount:.2f} — agent balance insufficient.\n"
        f"Top up the agent account, then reply <code>loaded</code> here to continue."
    )
    telegram_send_message(TOPUP_ALERT_GROUP_ID, alert)
    log(f"Top-up alert posted to {TOPUP_ALERT_GROUP_ID}; waiting up to {TOPUP_TIMEOUT_SEC}s for 'loaded' reply")

    start = time.time()
    offset = last_id + 1
    while time.time() - start < TOPUP_TIMEOUT_SEC:
        updates = telegram_get_updates(offset=offset, timeout=10)
        if not updates or not updates.get("ok"):
            time.sleep(2)
            continue
        for upd in updates.get("result", []):
            offset = upd["update_id"] + 1
            msg_data = upd.get("message") or upd.get("channel_post") or {}
            if str(msg_data.get("chat", {}).get("id", "")) != str(TOPUP_ALERT_GROUP_ID):
                continue
            text = (msg_data.get("text") or "").strip().lower()
            if "loaded" in text:
                log(f"Top-up confirmed by reply: {text!r}")
                telegram_send_message(TOPUP_ALERT_GROUP_ID, f"✅ Top-up confirmed — retrying recharge for <code>{player}</code> (agent: <code>{MILKY_WAY_USER}</code>)")
                return True
    log("Top-up wait timed out")
    return False


# ─────────────────────────────────────────────────────────────────────────────
# Milky Way page interactions
# ─────────────────────────────────────────────────────────────────────────────
def is_dashboard_visible(page: Page) -> bool:
    """Quick check: is the dashboard already loaded inside the main iframe?"""
    try:
        page.frame_locator('iframe[name="frm_main_content"]').locator(
            "input#txtSearch"
        ).wait_for(state="visible", timeout=3000)
        return True
    except PlaywrightTimeout:
        return False


def login_milky_way(page: Page) -> bool:
    """Navigate to login URL, handle CAPTCHA loop, return True iff dashboard reached."""
    # First: check if we're already on the dashboard from a prior run
    if is_dashboard_visible(page):
        log("Already logged in — refreshing to clear stale state")
        try:
            page.reload(wait_until="domcontentloaded", timeout=15000)
            page.wait_for_timeout(2000)
            force_clear_overlays(page)
        except Exception as e:
            log(f"Refresh failed (continuing anyway): {e}")
        # Verify dashboard is still reachable after refresh
        if is_dashboard_visible(page):
            log("Refresh successful — dashboard ready")
            return True
        # If refresh somehow knocked us off, fall through to login flow below
        log("Refresh landed off-dashboard — running full login")
    # Otherwise navigate fresh
    log(f"Navigating to {MILKY_WAY_URL}")
    page.goto(MILKY_WAY_URL, wait_until="domcontentloaded", timeout=45000)
    page.wait_for_timeout(2000)
    if is_dashboard_visible(page):
        log("Already logged in (post-nav)")
        return True

    for attempt in range(1, LOGIN_MAX_RETRIES + 1):
        log(f"Login attempt {attempt}/{LOGIN_MAX_RETRIES}")
        try:
            # Login form lives on the top-level page (no iframe wrapping login)
            # Dismiss any leftover error alert from the previous attempt
            try:
                for sel in [
                    'div#mb_con button:has-text("OK")',
                    'div#mb_con a:has-text("OK")',
                    'div#mb_con input[value="OK"]',
                    "div#mb_con >> text=OK",
                ]:
                    try:
                        page.locator(sel).first.click(timeout=1500)
                        page.wait_for_timeout(500)
                        break
                    except Exception:
                        continue
            except Exception:
                pass
            page.locator("input#txtLoginName").fill(MILKY_WAY_USER)
            page.locator("input#txtLoginPass").fill(MILKY_WAY_PASS)

            # Screenshot just the CAPTCHA image element
            captcha_bytes = page.locator("img#ImageCheck").screenshot()
            request_id = f"mw_{int(time.time())}"
            digits = solve_captcha_via_telegram(captcha_bytes, request_id)

            page.locator("input#txtVerifyCode").fill(digits)
            page.locator("input#btnLogin").click()
            page.wait_for_timeout(3500)

            if is_dashboard_visible(page):
                log("Login successful")
                force_clear_overlays(page)
                return True

            log("Dashboard didn't load — CAPTCHA likely wrong, retrying")
            # Loop again — page should now show a fresh CAPTCHA
            page.wait_for_timeout(1000)

        except TimeoutError as e:
            log(f"CAPTCHA timeout: {e}")
            return False
        except Exception as e:
            log(f"Attempt {attempt} exception: {e}")
            page.wait_for_timeout(1500)

    return False


def main_frame(page: Page) -> FrameLocator:
    return page.frame_locator('iframe[name="frm_main_content"]')


def dialog_frame(page: Page) -> FrameLocator:
    return page.frame_locator("div#DialogBySHF iframe")


def search_player(page: Page, account: str) -> dict | None:
    """
    Search by account, click Update on the result row, return {account, balance}.
    Returns None if no result found.
    """
    force_clear_overlays(page)
    main = main_frame(page)
    main.locator("input#txtSearch").fill(account)
    # Search link is an <a> with javascript:__doPostBack — click it
    main.locator('a:has-text("Search")').first.click()
    page.wait_for_timeout(1500)

    try:
        main.locator('a[onclick*="updateSelect"]').first.wait_for(
            state="visible", timeout=8000
        )
    except PlaywrightTimeout:
        return None

    # Click Update to open the per-player action panel
    main.locator('a[onclick*="updateSelect"]').first.click()
    page.wait_for_timeout(1500)

    # The red-text balance cell
    try:
        balance_text = main.locator('td[style*="color: red"]').first.inner_text().strip()
        balance = float(balance_text)
    except Exception:
        balance = 0.0

    return {"account": account, "balance": balance}


def read_agent_balance(page: Page) -> float | None:
    """Read 'Balance:NN' from top-of-page status bar (top level, NOT inside iframe)."""
    import re as _re
    try:
        # The label sits as plain text inside a top-level element on the dashboard
        text = page.locator("text=/Balance:\\s*\\d/").first.inner_text(timeout=3000)
        m = _re.search(r"Balance:\s*(\d+(?:\.\d+)?)", text)
        if m:
            return float(m.group(1))
    except Exception as e:
        log(f"read_agent_balance failed: {e}")
    return None


def wait_for_success_popup(page: Page, timeout_ms: int = 15000) -> tuple[str, object]:
    """
    Poll for #mb_con (the visible message box). Check both top page and main iframe.
    Returns (text, context) where context is the place we found it (page or frame_locator).
    """
    start = time.time()
    while (time.time() - start) * 1000 < timeout_ms:
        for ctx in (page, main_frame(page), dialog_frame(page)):
            try:
                box = ctx.locator("div#mb_con").first
                box.wait_for(state="visible", timeout=500)
                text = box.inner_text(timeout=1500).strip()
                return text, ctx
            except PlaywrightTimeout:
                continue
            except Exception:
                continue
        time.sleep(0.25)
    raise TimeoutError("Success popup did not appear within timeout")


def dismiss_popup(ctx) -> None:
    """Click whatever OK button is inside #mb_con. Be permissive — different forms have different markup."""
    for selector in [
        'div#mb_con button:has-text("OK")',
        'div#mb_con a:has-text("OK")',
        'div#mb_con input[value="OK"]',
        "div#mb_con >> text=OK",
    ]:
        try:
            ctx.locator(selector).first.click(timeout=2000)
            return
        except Exception:
            continue
    log("Could not dismiss popup — continuing anyway")


def force_clear_overlays(page: Page) -> None:
    """
    Nuclear option: forcibly hide any leftover mb_box/mb_con/DialogBySHFLayer
    overlays that intercept pointer events. Called before every action click.
    """
    js = """
    () => {
        const removeIds = ['DialogBySHF', 'DialogBySHFLayer'];
        const hideIds   = ['mb_box', 'mb_con', 'msgBoxDIV'];
        const purge = (doc) => {
            if (!doc) return;
            for (const id of removeIds) {
                const el = doc.getElementById(id);
                if (el) { el.remove(); }
            }
            for (const id of hideIds) {
                const el = doc.getElementById(id);
                if (el) { el.style.display = 'none'; el.innerHTML = ''; }
            }
        };
        purge(document);
        const f = document.querySelector('iframe[name="frm_main_content"]');
        if (f && f.contentDocument) { purge(f.contentDocument); }
        return true;
    }
    """
    try:
        page.evaluate(js)
    except Exception as e:
        log(f"force_clear_overlays ignored: {e}")


def _do_action_with_amount(
    page: Page, action_button_selector: str, amount: float
) -> tuple[str, object]:
    """Shared body of recharge & redeem: click action button, fill amount in dialog, submit, wait for popup."""
    # Milky Way accepts whole-dollar integers only — its onkeyup strips non-digits
    if amount != int(amount):
        raise ValueError(f"Milky Way accepts whole-dollar amounts only; got {amount}")
    amount_str = str(int(amount))
    force_clear_overlays(page)
    main = main_frame(page)
    main.locator(action_button_selector).first.click()
    page.wait_for_timeout(2000)

    dlg = dialog_frame(page)
    amount_input = dlg.locator("input#txtAddGold")
    amount_input.wait_for(state="visible", timeout=10000)
    # Give the iframe's JS a moment to initialize form state (ASP.NET ViewState)
    page.wait_for_timeout(800)

    # Clear field by setting empty value via JS (bypasses onkeyup interference), then type
    amount_input.evaluate("el => { el.value = ''; el.dispatchEvent(new Event('input', {bubbles: true})); }")
    page.wait_for_timeout(200)
    amount_input.press_sequentially(amount_str, delay=80)
    page.wait_for_timeout(300)
    actual = amount_input.input_value()
    if actual != amount_str:
        log(f"Amount field mismatch: wanted {amount_str!r}, got {actual!r}; forcing via JS set")
        amount_input.evaluate(
            f"el => {{ el.value = '{amount_str}'; el.dispatchEvent(new Event('input', {{bubbles: true}})); el.dispatchEvent(new Event('keyup', {{bubbles: true}})); }}"
        )
        page.wait_for_timeout(200)

    # Normal click — no force, no no_wait_after. ASP.NET needs both event firing
    # and post-click navigation handling to keep ViewState consistent.
    dlg.locator("input#Button1").click(timeout=10000)
    page.wait_for_timeout(1500)

    text, ctx = wait_for_success_popup(page)
    dismiss_popup(ctx)
    page.wait_for_timeout(2000)
    if "success" not in text.lower():
        raise RuntimeError(f"Unexpected popup text: {text!r}")
    return text, ctx


def recharge_player(page: Page, account: str, amount: float) -> dict:
    pre = search_player(page, account)
    if pre is None:
        raise ValueError(f"Player {account!r} not found")

    last_err = None
    for attempt in range(1, TOPUP_MAX_RETRIES + 1):
        try:
            _do_action_with_amount(page, 'a[onclick*="\'Recharge\'"]', amount)
            break
        except RuntimeError as e:
            msg = str(e).lower()
            insufficient = any(kw in msg for kw in ("insufficient", "surplus", "not enough"))
            if not insufficient:
                raise
            log(f"Recharge attempt {attempt}/{TOPUP_MAX_RETRIES} blocked — agent funds insufficient")
            last_err = e
            if attempt >= TOPUP_MAX_RETRIES:
                raise RuntimeError(
                    f"AGENT_FUNDS_EXHAUSTED: agent {MILKY_WAY_USER} still insufficient after {TOPUP_MAX_RETRIES} top-up requests for player {account} amount ${amount:.2f}"
                )
            if not wait_for_topup_signal(account, amount):
                raise RuntimeError("Timed out waiting for 'loaded' reply in Telegram")
            # Top-up confirmed — try Milky Way's native closeDialog(), then nuclear-hide
            # any stuck overlays, then re-search to reset the action panel cleanly.
            try:
                page.evaluate("() => { if (typeof closeDialog === 'function') { closeDialog(); } }")
            except Exception:
                pass
            force_clear_overlays(page)
            page.wait_for_timeout(1000)
            search_player(page, account)

    post = search_player(page, account)
    agent_balance = read_agent_balance(page)
    return {
        "balance_before": pre["balance"],
        "balance_after": post["balance"] if post else None,
        "agent_balance_after": agent_balance,
    }


def redeem_player(page: Page, account: str, amount: float) -> dict:
    pre = search_player(page, account)
    if pre is None:
        raise ValueError(f"Player {account!r} not found")

    _do_action_with_amount(page, 'a[onclick*="\'Redeem\'"]', amount)

    post = search_player(page, account)
    agent_balance = read_agent_balance(page)

    new_balance = post["balance"] if post else 0.0
    send_cashout_report(account, amount, new_balance, agent_balance)

    return {
        "balance_before": pre["balance"],
        "balance_after": new_balance,
        "agent_balance_after": agent_balance,
    }


def create_player(page: Page, account: str, password: str) -> dict:
    force_clear_overlays(page)
    main = main_frame(page)
    main.locator('a[onclick*="\'Create Account\'"]').click()
    page.wait_for_timeout(1500)

    dlg = dialog_frame(page)
    dlg.locator("input#txtAccount").wait_for(state="visible", timeout=10000)
    dlg.locator("input#txtAccount").fill(account)
    dlg.locator("input#txtLogonPass").fill(password)
    dlg.locator("input#txtLogonPass2").fill(password)

    # Submit button — try the most likely selectors in order
    for sel in [
        'input[type="button"][value="Create Player"]',
        'input[type="submit"][value="Create Player"]',
        'a:has-text("Create Player")',
        "button:has-text('Create Player')",
    ]:
        try:
            dlg.locator(sel).first.click(force=True, no_wait_after=True, timeout=2000)
            break
        except Exception:
            continue
    else:
        raise RuntimeError("Could not find Create Player submit button")

    page.wait_for_timeout(1000)
    try:
        text, ctx = wait_for_success_popup(page, timeout_ms=5000)
        if "exists" in text.lower() or "already" in text.lower():
            # Real error popup — surface it
            raise RuntimeError(f"Unexpected popup text: {text!r}")
        # Popup appeared and isn't an error — treat as success
        dismiss_popup(ctx)
        return {"created": True, "account": account}
    except (TimeoutError, PlaywrightTimeout) as e:
        # No popup appeared within timeout — verify by searching for the player
        log(f"No success popup detected — verifying create by search: {e}")
        page.wait_for_timeout(2000)
        force_clear_overlays(page)
        result = search_player(page, account)
        if result is not None:
            log(f"Player {account!r} found after create — treating as success")
            return {"created": True, "account": account}
        raise RuntimeError(f"Create submit completed but player {account!r} not found via search")


def reset_password(page: Page, account: str, new_password: str) -> dict:
    force_clear_overlays(page)
    pre = search_player(page, account)
    if pre is None:
        raise ValueError(f"Player {account!r} not found")

    main = main_frame(page)
    main.locator('a[onclick*="\'Reset Password\'"]').click()
    page.wait_for_timeout(1500)

    dlg = dialog_frame(page)
    dlg.locator("input#txtConfirmPass").wait_for(state="visible", timeout=10000)
    dlg.locator("input#txtConfirmPass").fill(new_password)
    dlg.locator("input#txtSureConfirmPass").fill(new_password)
    dlg.locator("input#Button1").click(force=True, no_wait_after=True, timeout=10000)
    page.wait_for_timeout(1000)

    text, ctx = wait_for_success_popup(page)
    if "success" not in text.lower():
        raise RuntimeError(f"Unexpected popup text: {text!r}")
    dismiss_popup(ctx)
    return {"reset": True, "account": account}


def get_balance(page: Page, account: str) -> dict:
    result = search_player(page, account)
    if result is None:
        raise ValueError(f"Player {account!r} not found")
    return result


# ─────────────────────────────────────────────────────────────────────────────
# CLI entry point
# ─────────────────────────────────────────────────────────────────────────────
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Milky Way automation")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("login", help="Just log in and confirm dashboard is reachable")

    pr = sub.add_parser("recharge")
    pr.add_argument("--player", required=True)
    pr.add_argument("--amount", type=float, required=True)

    pd = sub.add_parser("redeem")
    pd.add_argument("--player", required=True)
    pd.add_argument("--amount", type=float, required=True)

    pc = sub.add_parser("create")
    pc.add_argument("--account", required=True)
    pc.add_argument("--password", required=True)

    pt = sub.add_parser("reset")
    pt.add_argument("--player", required=True)
    pt.add_argument("--password", required=True)

    pb = sub.add_parser("balance")
    pb.add_argument("--player", required=True)

    return p


def validate_env() -> list[str]:
    missing = []
    for key in ("ADSPOWER_API_KEY", "MILKY_WAY_USER", "MILKY_WAY_PASS", "TELEGRAM_BOT_TOKEN"):
        if not os.getenv(key):
            missing.append(key)
    return missing


def main() -> None:
    args = build_parser().parse_args()

    missing = validate_env()
    if missing:
        fail(args.cmd, "MISSING_ENV", f"Set these in .env: {', '.join(missing)}")

    ws_url = None
    page = None
    started_by_us = False
    try:
        if ADSPOWER_REUSE_IF_OPEN:
            ws_url = adspower_status(ADSPOWER_PROFILE_ID)
            if ws_url:
                log(f"Reusing already-running profile, ws={ws_url}")
        if not ws_url:
            ws_url = adspower_start(ADSPOWER_PROFILE_ID)
            started_by_us = True
    except Exception as e:
        fail(args.cmd, "ADSPOWER_START_FAILED", str(e))

    try:
        with sync_playwright() as pw:
            browser = pw.chromium.connect_over_cdp(ws_url)
            context = browser.contexts[0] if browser.contexts else browser.new_context()
            page = context.pages[0] if context.pages else context.new_page()

            if not login_milky_way(page):
                screenshot = _save_screenshot(page, "login_failed")
                fail(args.cmd, "LOGIN_FAILED", "Could not reach dashboard", screenshot)

            if args.cmd == "login":
                emit({"status": "success", "action": "login"})
                return

            if args.cmd == "recharge":
                r = recharge_player(page, args.player, args.amount)
                emit({"status": "success", "action": "recharge",
                      "player": args.player, "amount": args.amount, **r})
                return

            if args.cmd == "redeem":
                r = redeem_player(page, args.player, args.amount)
                emit({"status": "success", "action": "redeem",
                      "player": args.player, "amount": args.amount, **r})
                return

            if args.cmd == "create":
                r = create_player(page, args.account, args.password)
                emit({"status": "success", "action": "create", **r})
                return

            if args.cmd == "reset":
                r = reset_password(page, args.player, args.password)
                emit({"status": "success", "action": "reset", **r})
                return

            if args.cmd == "balance":
                r = get_balance(page, args.player)
                emit({"status": "success", "action": "balance", **r})
                return

    except ValueError as e:
        # Caller error (e.g., player not found) — different error class
        screenshot = _save_screenshot(page, args.cmd)
        fail(args.cmd, "PLAYER_NOT_FOUND", str(e), screenshot)
    except TimeoutError as e:
        screenshot = _save_screenshot(page, args.cmd)
        msg = str(e)
        if "CAPTCHA" in msg or "captcha" in msg.lower():
            fail(args.cmd, "CAPTCHA_TIMEOUT", msg, screenshot)
        elif "popup" in msg.lower():
            fail(args.cmd, "POPUP_TIMEOUT", msg, screenshot)
        else:
            fail(args.cmd, "TIMEOUT", msg, screenshot)
    except PlaywrightTimeout as e:
        screenshot = _save_screenshot(page, args.cmd)
        fail(args.cmd, "PAGE_TIMEOUT", str(e), screenshot)
    except RuntimeError as e:
        screenshot = _save_screenshot(page, args.cmd)
        msg = str(e)
        if "AGENT_FUNDS_EXHAUSTED" in msg:
            fail(args.cmd, "AGENT_FUNDS_EXHAUSTED", msg, screenshot)
        else:
            fail(args.cmd, "RUNTIME", msg, screenshot)
    except Exception as e:
        screenshot = _save_screenshot(page, args.cmd)
        fail(args.cmd, "UNEXPECTED", f"{type(e).__name__}: {e}", screenshot)
    finally:
        # Only stop the profile if we started it AND keep-open is disabled
        if started_by_us and not ADSPOWER_KEEP_OPEN:
            adspower_stop(ADSPOWER_PROFILE_ID)
        elif ADSPOWER_KEEP_OPEN:
            log("Keeping AdsPower profile open for next command (set ADSPOWER_KEEP_OPEN=0 in .env to disable)")


def _save_screenshot(page, label: str) -> str | None:
    if page is None:
        return None
    try:
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        path = Path(f"error_{label}_{ts}.png").resolve()
        page.screenshot(path=str(path), full_page=True)
        return str(path)
    except Exception:
        return None


if __name__ == "__main__":
    main()
