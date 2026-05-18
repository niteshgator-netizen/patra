"""
Cash Machine automation - controls AdsPower-protected Chrome via Playwright.

Supports login, balance, recharge, redeem, create, and reset for Cash Machine.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path

import requests
from dotenv import load_dotenv
from playwright.sync_api import FrameLocator, Page, TimeoutError as PlaywrightTimeout, sync_playwright


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
load_dotenv(Path(__file__).with_name(".env"))

ADSPOWER_API = os.getenv("ADSPOWER_API", "http://127.0.0.1:50325")
ADSPOWER_PROFILE_ID = os.getenv("ADSPOWER_PROFILE_ID", "")
ADSPOWER_API_KEY = os.getenv("ADSPOWER_API_KEY", "")
ADSPOWER_KEEP_OPEN = os.getenv("ADSPOWER_KEEP_OPEN", "1") == "1"
ADSPOWER_REUSE_IF_OPEN = os.getenv("ADSPOWER_REUSE_IF_OPEN", "1") == "1"
CASH_MACHINE_USER = os.getenv("CASH_MACHINE_USER", "")
CASH_MACHINE_PASS = os.getenv("CASH_MACHINE_PASS", "")
CASH_MACHINE_LOGIN_URL = os.getenv(
    "CASH_MACHINE_LOGIN_URL", "https://agentserver.cashmachine777.com/admin/login"
)
CASH_MACHINE_DASHBOARD_URL = os.getenv(
    "CASH_MACHINE_DASHBOARD_URL", "https://agentserver.cashmachine777.com/admin"
)
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
CAPTCHA_GROUP_ID = os.getenv("CAPTCHA_GROUP_ID", "-5214874121")
CASHOUT_GROUP_ID = os.getenv("CASHOUT_GROUP_ID", "-5243223053")
TOPUP_ALERT_GROUP_ID = os.getenv("TOPUP_ALERT_GROUP_ID", CASHOUT_GROUP_ID)
CAPTCHA_TIMEOUT_SEC = int(os.getenv("CAPTCHA_TIMEOUT_SEC", "90"))
LOGIN_MAX_RETRIES = int(os.getenv("LOGIN_MAX_RETRIES", "3"))
TOPUP_TIMEOUT_SEC = int(os.getenv("TOPUP_TIMEOUT_SEC", "1800"))
TOPUP_MAX_RETRIES = int(os.getenv("TOPUP_MAX_RETRIES", "3"))


# ---------------------------------------------------------------------------
# Output helpers - every script run ends with exactly one JSON line on stdout.
# ---------------------------------------------------------------------------
def emit(payload: dict) -> None:
    print(json.dumps(payload, separators=(",", ":")))


def fail(action: str, code: str, message: str, screenshot: str | None = None) -> None:
    out = {"status": "error", "action": action, "error_code": code, "error_message": message}
    if screenshot:
        out["screenshot"] = screenshot
    emit(out)
    sys.exit(1)


def log(msg: str) -> None:
    """Diagnostic output stays on stderr so stdout remains machine-readable JSON."""
    print(f"[cash_machine] {msg}", file=sys.stderr, flush=True)


# ---------------------------------------------------------------------------
# AdsPower Local API
# ---------------------------------------------------------------------------
def adspower_start(profile_id: str) -> str:
    """Start the profile browser and return the puppeteer WebSocket URL."""
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


def adspower_status(profile_id: str) -> str | None:
    """Return an active profile's CDP WebSocket URL, if it is already running."""
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


# ---------------------------------------------------------------------------
# Telegram
# ---------------------------------------------------------------------------
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
    files = {"photo": ("cash_machine_captcha.png", photo_bytes, "image/png")}
    data = {"chat_id": chat_id, "caption": caption}
    r = requests.post(url, files=files, data=data, timeout=30)
    return r.json()


@safe_telegram
def telegram_get_updates(offset: int | None = None, timeout: int = 5) -> dict | None:
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/getUpdates"
    params: dict = {"timeout": timeout}
    if offset is not None:
        params["offset"] = offset
    r = requests.get(url, params=params, timeout=timeout + 10)
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


def send_cashout_report(player: str, amount: float, balance_after: float, agent_balance: float | None) -> None:
    """Post a redeem cashout summary to the cashout Telegram group. Wrapped in
    safe_telegram via telegram_send_message — never raises."""
    agent_str = f"${agent_balance:.2f}" if agent_balance is not None else "unknown"
    text = (
        f"💸 CASHOUT | Cash Machine\n"
        f"Player: <code>{player}</code>\n"
        f"Amount: ${amount:.2f}\n"
        f"Player balance after: ${balance_after:.2f}\n"
        f"Agent balance after: {agent_str}"
    )
    telegram_send_message(CASHOUT_GROUP_ID, text)
    log(f"Cashout report posted to {CASHOUT_GROUP_ID}: {player} ${amount:.2f}")


# ---------------------------------------------------------------------------
# Cash Machine login helpers
# ---------------------------------------------------------------------------
def is_dashboard_url(url: str) -> bool:
    url = url.lower()
    return "/admin" in url and "/admin/login" not in url


def current_layui_message(page: Page) -> str:
    try:
        layers = page.locator("div.layui-layer")
        for i in range(layers.count() - 1, -1, -1):
            layer = layers.nth(i)
            try:
                if layer.is_visible(timeout=300):
                    return layer.inner_text(timeout=1000).strip()
            except Exception:
                continue
    except Exception:
        pass
    return ""


def solve_canvas_captcha(page: Page) -> str:
    """Capture canvas CAPTCHA, send it to Telegram, wait for a 4-char reply, and fill it."""
    initial = telegram_get_updates(timeout=0)
    last_id = 0
    if initial and initial.get("ok"):
        last_id = max((u["update_id"] for u in initial.get("result", [])), default=0)

    canvas = page.locator("canvas#verifyCanvas")
    canvas.wait_for(state="attached", timeout=10000)
    page.wait_for_timeout(500)

    data_url = page.evaluate(
        """
        () => {
            const c = document.querySelector('canvas#verifyCanvas');
            return c ? c.toDataURL('image/png') : null;
        }
        """
    )
    if not data_url or not isinstance(data_url, str) or not data_url.startswith("data:image/png;base64,"):
        raise RuntimeError(f"Could not extract CAPTCHA canvas via toDataURL (got {type(data_url).__name__})")
    image_bytes = base64.b64decode(data_url.split(",", 1)[1])

    temp_path = None
    with tempfile.NamedTemporaryFile(prefix="cash_machine_captcha_", suffix=".png", delete=False) as tmp:
        tmp.write(image_bytes)
        temp_path = tmp.name

    telegram_send_photo(CAPTCHA_GROUP_ID, image_bytes, "Cash Machine login")
    log(f"CAPTCHA captured via toDataURL, posted to Telegram ({temp_path})")

    code_re = re.compile(r"^\s*([A-Za-z0-9]{4})\s*$")
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
            match = code_re.match(text)
            if match:
                code = match.group(1)
                page.locator('input[name="captcha"]').fill(code)
                log(f"CAPTCHA solved: {code}")
                return code

    raise TimeoutError(f"CAPTCHA not solved within {CAPTCHA_TIMEOUT_SEC}s")


def wait_for_login_result(page: Page, timeout_ms: int = 10000) -> tuple[str, str]:
    """Return ('success'|'captcha_error'|'timeout', message)."""
    error_re = re.compile(r"verification|incorrect|captcha|wrong", re.IGNORECASE)
    deadline = time.time() + timeout_ms / 1000
    while time.time() < deadline:
        if is_dashboard_url(page.url):
            return "success", ""
        message = current_layui_message(page)
        if message and error_re.search(message):
            return "captcha_error", message
        page.wait_for_timeout(300)
    if is_dashboard_url(page.url):
        return "success", ""
    return "timeout", current_layui_message(page)


def reload_dashboard_ready(page: Page) -> None:
    page.goto(CASH_MACHINE_DASHBOARD_URL)
    page.wait_for_load_state("domcontentloaded", timeout=10000)
    page.wait_for_timeout(1000)
    dismiss_layui_popups(page)
    page.wait_for_selector("iframe#mainBody", state="attached", timeout=10000)
    disable_header_interception(page)
    print("[cash_machine] Dashboard reloaded and ready", file=sys.stderr, flush=True)


def login_cash_machine(page: Page) -> bool:
    """Navigate to Cash Machine login, solve canvas CAPTCHA, and reach dashboard."""
    if is_dashboard_url(page.url):
        log(f"Already on dashboard (url={page.url}) - skipping login flow")
        dismiss_layui_popups(page)
        reload_dashboard_ready(page)
        return True

    log(f"Navigating to {CASH_MACHINE_LOGIN_URL}")
    page.goto(CASH_MACHINE_LOGIN_URL, wait_until="domcontentloaded", timeout=45000)
    page.wait_for_timeout(1000)

    if is_dashboard_url(page.url):
        log("Already logged in - refreshing to clear stale state")
        dismiss_layui_popups(page)
        page.reload(wait_until="domcontentloaded", timeout=15000)
        page.wait_for_timeout(1000)
        dismiss_layui_popups(page)
        log("Login success, on dashboard")
        reload_dashboard_ready(page)
        return True

    for attempt in range(1, LOGIN_MAX_RETRIES + 1):
        log(f"Login attempt {attempt}/{LOGIN_MAX_RETRIES}")
        dismiss_layui_popups(page)
        page.locator('input[name="username"]').fill(CASH_MACHINE_USER)
        page.locator('input[name="password"]').fill(CASH_MACHINE_PASS)
        solve_canvas_captcha(page)

        try:
            btn = page.locator('button.layui-btn[lay-filter="login"]').first
            btn.scroll_into_view_if_needed(timeout=2000)
            btn.click(timeout=3000)
        except Exception as e1:
            log(f"Login click attempt 1 failed ({e1}), trying force click")
            try:
                page.locator('button.layui-btn[lay-filter="login"]').first.click(force=True, timeout=3000)
            except Exception as e2:
                log(f"Login click attempt 2 failed ({e2}), trying JS click")
                page.evaluate(
                    """
                    () => {
                        const btn = document.querySelector('button.layui-btn[lay-filter="login"]');
                        if (!btn) throw new Error('login button not found in DOM');
                        btn.click();
                    }
                    """
                )
        print(f"[cash_machine] post-submit URL: {page.url}", file=sys.stderr, flush=True)
        result, message = wait_for_login_result(page)
        if result == "success":
            dismiss_layui_popups(page)
            log("Login success, on dashboard")
            reload_dashboard_ready(page)
            return True

        if result == "captcha_error" and attempt < LOGIN_MAX_RETRIES:
            log(f"CAPTCHA rejected by server, refreshing and retrying (attempt {attempt + 1}/{LOGIN_MAX_RETRIES})")
            dismiss_layui_popups(page)
            try:
                page.locator("canvas#verifyCanvas").click(timeout=3000)
            except Exception as e:
                log(f"CAPTCHA refresh click ignored: {e}")
            page.wait_for_timeout(500)
            continue

        if is_dashboard_url(page.url):
            dismiss_layui_popups(page)
            log("Login success, on dashboard")
            reload_dashboard_ready(page)
            return True

        log(f"Login verdict timed out or failed; url={page.url!r}; layui_message={message!r}")
        if message:
            raise RuntimeError(f"Login failed: {message}")
        raise TimeoutError("Login did not reach dashboard before timeout")

    return False


# ---------------------------------------------------------------------------
# Cash Machine action helpers
# ---------------------------------------------------------------------------
class PlayerNotFound(ValueError):
    pass


class ActionFailed(RuntimeError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


def parse_money(text: str) -> float:
    match = re.search(r"-?[\d,]+(?:\.\d+)?", text.replace("$", ""))
    if not match:
        raise ValueError(f"Could not parse money value from {text!r}")
    return float(match.group(0).replace(",", ""))


def get_main_frame(page: Page) -> FrameLocator:
    page.wait_for_selector("iframe#mainBody", state="attached", timeout=10000)
    return page.frame_locator("iframe#mainBody")


def get_user_management_frame(page: Page) -> FrameLocator:
    """Returns the User Management tab iframe (sibling of mainBody at top level)."""
    selector = 'iframe[src*="/admin/player/index"]'
    page.wait_for_selector(selector, state="attached", timeout=10000)
    return page.frame_locator(selector)


def get_user_management_frame_if_present(page: Page) -> FrameLocator | None:
    try:
        if page.locator('iframe[src*="/admin/player/index"]').count() > 0:
            return page.frame_locator('iframe[src*="/admin/player/index"]')
    except Exception:
        pass
    return None


def get_dialog_frame(page: Page, expected_url_substring: str, timeout_ms: int = 10000) -> FrameLocator:
    """Dialog iframes (layui-layer-iframeN) appear inside the User Management tab iframe."""
    um = get_user_management_frame(page)
    selector = f'iframe[src*="{expected_url_substring}"]'
    try:
        um.locator(selector).last.wait_for(state="attached", timeout=timeout_ms)
    except PlaywrightTimeout as e:
        raise TimeoutError(
            f"Dialog iframe for {expected_url_substring} did not appear within {timeout_ms}ms"
        ) from e
    return um.frame_locator(selector)


def dismiss_layui_popups(page: Page) -> None:
    """Close or remove layui popups. Safe when no popup is present."""
    cleared = 0
    for ctx in (page, get_main_frame_if_present(page), get_user_management_frame_if_present(page)):
        if ctx is None:
            continue
        try:
            layers = ctx.locator("div.layui-layer")
            count = layers.count()
            if count == 0:
                continue
            for selector in (
                "a.layui-layer-ico.layui-layer-close",
                "a.layui-layer-btn0",
            ):
                try:
                    buttons = ctx.locator(selector)
                    for i in range(buttons.count() - 1, -1, -1):
                        try:
                            buttons.nth(i).click(timeout=500)
                            cleared += 1
                            page.wait_for_timeout(200)
                        except Exception:
                            continue
                except Exception:
                    continue
        except Exception as e:
            log(f"layui popup click dismiss ignored: {e}")

    try:
        removed = page.evaluate(
            """
            () => {
                let count = 0;
                function clean(doc) {
                    if (!doc) return 0;
                    let c = 0;
                    doc.querySelectorAll('.layui-layer').forEach(el => { el.remove(); c += 1; });
                    doc.querySelectorAll('.layui-layer-shade').forEach(el => { el.remove(); c += 1; });
                    doc.querySelectorAll('.layui-layer-move').forEach(el => { el.remove(); c += 1; });
                    return c;
                }
                count += clean(document);
                document.querySelectorAll('iframe').forEach(f => {
                    try { count += clean(f.contentDocument); } catch (e) {}
                    try {
                        const nested = f.contentDocument && f.contentDocument.querySelectorAll('iframe');
                        if (nested) nested.forEach(n => {
                            try { count += clean(n.contentDocument); } catch (e) {}
                        });
                    } catch (e) {}
                });
                return count;
            }
            """
        )
        cleared += int(removed or 0)
    except Exception as e:
        log(f"layui popup JS dismiss ignored: {e}")

    if cleared:
        log(f"dismiss_layui_popups: cleared {cleared} popup(s)")


def get_main_frame_if_present(page: Page) -> FrameLocator | None:
    try:
        if page.locator("iframe#mainBody").count() > 0:
            return page.frame_locator("iframe#mainBody")
    except Exception:
        pass
    return None


HEADER_HIDE_CSS = """
.layui-header.okadmin-header,
.layui-header.okadmin-header *,
.layui-tab-title,
.layui-tab-title *,
.layui-tab.ok-tab > ul.layui-tab-title,
.layui-tab.ok-tab > ul.layui-tab-title *,
div[lay-filter="ok-tab"] > .layui-tab-title,
div[lay-filter="ok-tab"] > .layui-tab-title *,
.layui-layer-shade {
    pointer-events: none !important;
}
"""


def disable_header_interception(page: Page) -> None:
    """Disable pointer events on dashboard chrome that intercepts click targets:
    the okadmin header AND the layui tab title strip. Injects CSS into the top
    page and every iframe (main + UM + any nested), since the tab strip exists
    inside iframes too. Idempotent — uses a data attribute to avoid duplicates."""
    try:
        page.add_style_tag(content=HEADER_HIDE_CSS)
    except Exception as e:
        log(f"disable_header_interception (top page) ignored: {e}")
    try:
        page.evaluate(
            """
            (css) => {
                function inject(doc) {
                    if (!doc || !doc.head) return false;
                    if (doc.querySelector('style[data-patra-overlay-fix]')) return false;
                    const style = doc.createElement('style');
                    style.setAttribute('data-patra-overlay-fix', '1');
                    style.textContent = css;
                    doc.head.appendChild(style);
                    return true;
                }
                let count = 0;
                if (inject(document)) count += 1;
                document.querySelectorAll('iframe').forEach(f => {
                    try {
                        if (inject(f.contentDocument)) count += 1;
                        const nested = f.contentDocument && f.contentDocument.querySelectorAll('iframe');
                        if (nested) nested.forEach(n => {
                            try { if (inject(n.contentDocument)) count += 1; } catch (e) {}
                        });
                    } catch (e) {}
                });
                return count;
            }
            """,
            HEADER_HIDE_CSS,
        )
        log("disable_header_interception: pointer-events disabled in all frames")
    except Exception as e:
        log(f"disable_header_interception (iframes) ignored: {e}")


def open_user_management_tab(page: Page) -> None:
    # Click sidebar link on TOP page (sidebar is not inside any iframe)
    try:
        link = page.locator('a[data-url="/admin/player/index"]').first
        if not link.is_visible(timeout=1500):
            try:
                page.locator('a:has(cite:has-text("Game User"))').first.click(timeout=3000)
                page.wait_for_timeout(300)
            except Exception:
                pass
        link = page.locator('a[data-url="/admin/player/index"]').first
        link.click(timeout=5000)
    except Exception:
        page.evaluate(
            """
            () => {
                const a = document.querySelector('a[data-url="/admin/player/index"]');
                if (a) a.click();
            }
            """
        )

    page.wait_for_timeout(800)

    # Wait for the top-level User Management iframe (sibling of mainBody)
    try:
        page.wait_for_selector('iframe[src*="/admin/player/index"]', state="attached", timeout=10000)
    except PlaywrightTimeout:
        page.evaluate(
            """
            () => {
                const a = document.querySelector('a[data-url="/admin/player/index"]');
                if (a) a.click();
            }
            """
        )
        page.wait_for_timeout(1000)
        page.wait_for_selector('iframe[src*="/admin/player/index"]', state="attached", timeout=8000)

    # Now wait for the search form INSIDE the User Management iframe
    um = get_user_management_frame(page)
    um.locator('input[name="account"]').first.wait_for(state="visible", timeout=10000)

    dismiss_layui_popups(page)


def search_player(page: Page, username: str):
    open_user_management_tab(page)
    um = get_user_management_frame(page)
    um.locator('input[name="account"]').first.fill(username)
    _clicked = False
    for selector in ('button.layui-btn[lay-filter="search"]', 'button[lay-submit][lay-filter="search"]'):
        try:
            btn = um.locator(selector).first
            btn.scroll_into_view_if_needed(timeout=1500)
            btn.click(timeout=3000)
            _clicked = True
            break
        except Exception as e1:
            log(f"Search click via {selector} normal failed ({e1}); trying force click")
            try:
                um.locator(selector).first.click(force=True, timeout=2000)
                _clicked = True
                break
            except Exception as e2:
                log(f"Search click via {selector} force failed ({e2}); trying JS click")
                try:
                    page.evaluate(f"""
                        () => {{
                            const um = document.querySelector('iframe[src*="/admin/player/index"]');
                            if (!um || !um.contentDocument) throw new Error('UM iframe not accessible');
                            const btn = um.contentDocument.querySelector('{selector}');
                            if (!btn) throw new Error('search button not found');
                            btn.click();
                        }}
                    """)
                    _clicked = True
                    break
                except Exception as e3:
                    log(f"Search click via {selector} JS failed ({e3})")
                    continue

    if not _clicked:
        raise RuntimeError("Could not click search button after all strategies")

    row = um.locator(f'tr:has-text("{username}")').first
    try:
        row.wait_for(state="visible", timeout=8000)
    except PlaywrightTimeout as e:
        raise PlayerNotFound(username) from e
    return row


def read_row_balance(row) -> float:
    for selector in ('td[data-field="score"]', 'td[data-field="balance"]'):
        try:
            cell = row.locator(selector).first
            if cell.count() > 0:
                return parse_money(cell.inner_text(timeout=2000))
        except Exception:
            continue
    return parse_money(row.locator("td").nth(5).inner_text(timeout=2000))


def read_agent_balance(page: Page) -> float | None:
    """Read the agent's available balance from the top-right header.
    Header text format: 'Balance: 154.00' on the top page (not inside any iframe).
    """
    patterns = (
        r"Balance\s*[:：]\s*\$?([\d,]+(?:\.\d+)?)",
    )
    for selector in (
        "div.layui-layout-right",
        "div.layui-header",
        ".okadmin-header",
        "body",
    ):
        try:
            loc = page.locator(selector).first
            if loc.count() > 0:
                text = loc.inner_text(timeout=1500)
                for pattern in patterns:
                    match = re.search(pattern, text, re.IGNORECASE)
                    if match:
                        value = parse_money(match.group(1))
                        log(f"read_agent_balance: {value} (via selector {selector})")
                        return value
        except Exception:
            continue
    try:
        text = page.evaluate("() => document.body.innerText || ''")
        if isinstance(text, str):
            for pattern in patterns:
                match = re.search(pattern, text, re.IGNORECASE)
                if match:
                    value = parse_money(match.group(1))
                    log(f"read_agent_balance: {value} (via JS body scan)")
                    return value
    except Exception as e:
        log(f"read_agent_balance JS scan ignored: {e}")
    log("could not read agent balance")
    return None


def read_dialog_money(dialog: FrameLocator, selectors: tuple[str, ...]) -> float | None:
    for selector in selectors:
        try:
            loc = dialog.locator(selector).first
            loc.wait_for(state="visible", timeout=2000)
            value = loc.input_value(timeout=1000)
            if value:
                return parse_money(value)
        except Exception:
            try:
                text = dialog.locator(selector).first.inner_text(timeout=1000)
                if text:
                    return parse_money(text)
            except Exception:
                continue
    return None


def dialog_appeared(page, expected_url_substring: str, timeout_ms: int = 2500) -> bool:
    """Returns True if a dialog iframe with the expected src substring appears inside the UM iframe within timeout_ms."""
    try:
        um = get_user_management_frame_if_present(page)
        if um is None:
            return False
        um.locator(f'iframe[src*="{expected_url_substring}"]').last.wait_for(
            state="attached", timeout=timeout_ms
        )
        return True
    except Exception:
        return False


def click_row_action(row, lay_event: str, label: str, page=None, username: str = None, expected_dialog_url: str = None) -> None:
    """Click an action link/button on a player row.
    
    Uses Playwright force-click (confirmed working on this site). Normal clicks fail
    due to header pointer-event interception; raw JS .click() doesn't fire layui's
    lay-event delegated handlers. After each attempt, if expected_dialog_url is set,
    verifies the dialog actually appeared before declaring success.
    """
    selectors = (
        f'a[lay-event="{lay_event}"]',
        f'button[lay-event="{lay_event}"]',
        f'a:has-text("{label}")',
        f'button:has-text("{label}")',
    )

    def _verify_or_fallthrough(strategy_label: str) -> bool:
        if expected_dialog_url is None:
            log(f"click_row_action: {strategy_label} reported success (no dialog verification)")
            return True
        if dialog_appeared(page, expected_dialog_url, timeout_ms=2500):
            log(f"click_row_action: {strategy_label} — dialog appeared")
            return True
        log(f"click_row_action: {strategy_label} reported success but dialog never appeared, falling through")
        return False

    # Strategy 1: Playwright force-click on the scoped row (confirmed working last run).
    for sel in selectors:
        try:
            row.locator(sel).first.click(force=True, timeout=2500)
            log(f"click_row_action: force-clicked {sel} in scoped row")
            if _verify_or_fallthrough(f"force {sel} scoped row"):
                return
        except Exception as e:
            log(f"click_row_action: force {sel} scoped row failed: {type(e).__name__}: {str(e)[:120]}")

    # Strategy 2: Playwright normal click on scoped row (in case header is now neutralized).
    for sel in selectors:
        try:
            row.locator(sel).first.click(timeout=2500)
            log(f"click_row_action: normal-clicked {sel} in scoped row")
            if _verify_or_fallthrough(f"normal {sel} scoped row"):
                return
        except Exception as e:
            log(f"click_row_action: normal {sel} scoped row failed: {type(e).__name__}: {str(e)[:120]}")

    # Strategy 3: Playwright force-click anywhere in UM iframe matching the username's row.
    # If row locator went stale, this re-queries from UM root.
    if page is not None and username:
        try:
            um = get_user_management_frame(page)
            rescoped = um.locator(f'tr:has-text("{username}")').last
            for sel in selectors:
                try:
                    rescoped.locator(sel).first.click(force=True, timeout=2500)
                    log(f"click_row_action: force-clicked {sel} in rescoped UM row (last)")
                    if _verify_or_fallthrough(f"force {sel} rescoped UM"):
                        return
                except Exception as e:
                    log(f"click_row_action: force {sel} rescoped UM failed: {type(e).__name__}: {str(e)[:120]}")
        except Exception as e:
            log(f"click_row_action: rescoped UM setup failed: {type(e).__name__}: {str(e)[:160]}")

    raise RuntimeError(f"Could not find or successfully trigger {label} action for player row")


def close_latest_dialog(page: Page) -> None:
    main = get_main_frame_if_present(page)
    for ctx in (main, page):
        if ctx is None:
            continue
        for selector in ("a.layui-layer-ico.layui-layer-close", "a.layui-layer-close"):
            try:
                ctx.locator(selector).last.click(timeout=1000)
                page.wait_for_timeout(500)
                return
            except Exception:
                continue


def current_action_message(page: Page) -> str:
    """Collect visible layui-layer message text from EVERY frame in the page tree
    (top page, mainBody, User Management, AND open dialog iframes like /insert,
    /recharge, /withdraw, /resetpw). Validation popups from cash_machine often appear
    INSIDE the dialog iframe — scanning only top-level frames misses them.
    Excludes iframe-dialog containers and loading layers so dialog titles
    (e.g. 'Add user', 'Withdraw') don't get falsely reported as messages."""
    try:
        result = page.evaluate(
            """
            () => {
                const messages = [];
                function scan(doc) {
                    if (!doc) return;
                    const layers = Array.from(
                        doc.querySelectorAll(
                            'div.layui-layer:not(.layui-layer-iframe):not(.layui-layer-loading)'
                        )
                    );
                    for (let i = layers.length - 1; i >= 0; i--) {
                        const layer = layers[i];
                        const style = layer.ownerDocument.defaultView.getComputedStyle(layer);
                        if (style.display === 'none' || style.visibility === 'hidden') continue;
                        const text = (layer.innerText || '').trim();
                        if (text) messages.push(text);
                    }
                }
                function walk(doc, depth) {
                    if (!doc || depth > 5) return;
                    scan(doc);
                    const iframes = doc.querySelectorAll('iframe');
                    iframes.forEach(f => {
                        try { walk(f.contentDocument, depth + 1); } catch (e) {}
                    });
                }
                walk(document, 0);
                return messages.join('\\n');
            }
            """
        )
        return (result or "").strip()
    except Exception as e:
        log(f"current_action_message scan ignored: {e}")
        return ""


def has_player_dialog_open(page: Page) -> bool:
    """Returns True only if an ACTION dialog iframe is open (recharge/withdraw/insert/
    resetpw/etc.) — explicitly excludes the User Management tab itself (/admin/player/index)
    so 'dialog closed' detection works correctly."""
    action_paths = ("recharge", "withdraw", "insert", "resetpw", "reset", "edit")
    for ctx in (page, get_main_frame_if_present(page), get_user_management_frame_if_present(page)):
        if ctx is None:
            continue
        for path in action_paths:
            try:
                frames = ctx.locator(f'iframe[src*="/admin/player/{path}"]')
                for i in range(frames.count()):
                    try:
                        if frames.nth(i).is_visible(timeout=200):
                            return True
                    except Exception:
                        continue
            except Exception:
                continue
    return False


def wait_for_action_success(page: Page, timeout_ms: int = 12000) -> str:
    """Wait for confirmed action success. Raises on timeout-with-validation-text (not silent success)."""
    success_re = re.compile(r"success|succeeded|successful|成功", re.IGNORECASE)
    error_re = re.compile(
        r"fail|failed|error|incorrect|insufficient|not enough|exists|already|失败|"
        r"must contain|must be|only be|can only|between\s+\d|cannot|invalid|"
        r"please enter|please input|不能|请输入|必须",
        re.IGNORECASE,
    )
    receipt_re = re.compile(r"(GAMEROOM|CASH\s*MACHINE|MAFIA|MR\s*ALL.*ONE|CASH\s*FRENZY).*(DEPOSIT|WITHDRAW|TOTAL\s*BALANCE)", re.IGNORECASE | re.DOTALL)
    deadline = time.time() + timeout_ms / 1000
    last_message = ""
    saw_dialog = has_player_dialog_open(page)
    while time.time() < deadline:
        message = current_action_message(page)
        if message:
            last_message = message
            if receipt_re.search(message):
                log(f"wait_for_action_success: receipt modal detected")
                try:
                    for btn_text in ("Close", "close", "Cancel", "确定", "OK"):
                        try:
                            page.locator(f'.layui-layer-btn0:has-text("{btn_text}"), .layui-layer button:has-text("{btn_text}")').first.click(timeout=800)
                            break
                        except Exception:
                            continue
                except Exception:
                    pass
                return message
            if error_re.search(message):
                raise ActionFailed("ACTION_FAILED", message)
            if success_re.search(message):
                return message
        if saw_dialog and not has_player_dialog_open(page):
            return "Dialog closed"
        page.wait_for_timeout(100)
    # Final fallback: if a dialog WAS open at function entry and is NOT open now,
    # treat dialog closure as implicit success (cash_machine often closes the dialog
    # silently rather than showing a toast). The caller's own post-action check
    # (e.g. balance changed, search returns updated row) is the real verification.
    if saw_dialog and not has_player_dialog_open(page):
        return "Dialog closed (no toast)"
    if last_message:
        raise ActionFailed("ACTION_INCONCLUSIVE", f"No success signal within {timeout_ms}ms. Last message: {last_message!r}")
    raise TimeoutError("Action success toast did not appear")


def wait_for_topup_signal(player: str, amount: float) -> bool:
    initial = telegram_get_updates(timeout=0)
    last_id = 0
    if initial and initial.get("ok"):
        last_id = max((u["update_id"] for u in initial.get("result", [])), default=0)

    alert = (
        f"AGENT FUNDS NEEDED | Cash Machine\n"
        f"Agent: {CASH_MACHINE_USER}\n"
        f"Cannot recharge {player} for ${amount:.2f} — agent balance insufficient.\n"
        "Top up the agent account, then reply 'loaded' here to continue."
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
                return True
    log("Top-up wait timed out")
    return False


def fill_amount(input_locator, amount: float) -> None:
    amount_text = str(int(amount)) if amount == int(amount) else str(amount)
    input_locator.fill("")
    input_locator.fill(amount_text)


def get_balance(page: Page, account: str) -> dict:
    dismiss_layui_popups(page)
    disable_header_interception(page)
    row = search_player(page, account)
    balance = read_row_balance(row)
    dismiss_layui_popups(page)
    return {"status": "success", "action": "balance", "account": account, "balance": balance}


def recharge_player(page: Page, account: str, amount: float) -> dict:
    dismiss_layui_popups(page)
    disable_header_interception(page)
    balance_before = None
    for attempt in range(1, TOPUP_MAX_RETRIES + 1):
        row = search_player(page, account)
        balance_before = read_row_balance(row)
        click_row_action(
            row,
            "recharge",
            "Recharge",
            page=page,
            username=account,
            expected_dialog_url="/admin/player/recharge",
        )
        dialog = get_dialog_frame(page, "/admin/player/recharge")
        dialog_balance = read_dialog_money(dialog, ('input[name="score"]', 'input[name="player_balance"]'))
        if dialog_balance is not None:
            balance_before = dialog_balance
        agent_balance_before = read_dialog_money(
            dialog,
            ('input[name="available_balance"]', 'input[name="agent_balance"]', 'input[name="surplus"]'),
        )
        if agent_balance_before is None:
            agent_balance_before = read_agent_balance(page)

        if agent_balance_before is not None and amount > agent_balance_before:
            log(f"Recharge attempt {attempt}/{TOPUP_MAX_RETRIES} blocked - agent funds insufficient")
            if attempt >= TOPUP_MAX_RETRIES:
                raise RuntimeError(
                    f"AGENT_FUNDS_EXHAUSTED: agent {CASH_MACHINE_USER} still insufficient after {TOPUP_MAX_RETRIES} top-up requests for player {account} amount ${amount:.2f}"
                )
            if not wait_for_topup_signal(account, amount):
                raise RuntimeError("Timed out waiting for 'loaded' reply in Telegram")

            # After a long Telegram wait (up to TOPUP_TIMEOUT_SEC = 30min), the cash_machine
            # session has likely expired. Re-navigate to the dashboard and call
            # login_cash_machine() — it's idempotent: returns immediately if session is still
            # valid, runs full CAPTCHA re-login if expired. Then re-inject the overlay
            # CSS (page reload wipes our <style> tag) and clear any popups before
            # looping back to the next search_player attempt.
            log(f"Post-topup: refreshing session before retry attempt {attempt + 1}")
            try:
                page.goto(CASH_MACHINE_DASHBOARD_URL, wait_until="domcontentloaded", timeout=30000)
                page.wait_for_timeout(1500)
            except Exception as e:
                log(f"Post-topup navigate ignored: {e}")
            if not login_cash_machine(page):
                raise RuntimeError(f"Session lost after top-up wait; re-login failed for player {account}")
            disable_header_interception(page)
            dismiss_layui_popups(page)
            page.wait_for_timeout(1000)
            continue

        fill_amount(dialog.locator('input[name="balance"]').first, amount)
        dialog.locator('button.layui-btn[lay-filter="recharge"]').first.click()
        wait_for_action_success(page)
        dismiss_layui_popups(page)
        post = search_player(page, account)
        balance_after = read_row_balance(post)
        dismiss_layui_popups(page)
        return {
            "status": "success",
            "action": "recharge",
            "player": account,
            "amount": amount,
            "balance_before": balance_before,
            "balance_after": balance_after,
            "agent_balance_after": read_agent_balance(page),
        }

    raise RuntimeError(f"Recharge failed for player {account}")


def redeem_player(page: Page, account: str, amount: float) -> dict:
    dismiss_layui_popups(page)
    disable_header_interception(page)
    row = search_player(page, account)
    balance_before = read_row_balance(row)
    click_row_action(
        row,
        "withdraw",
        "Withdraw",
        page=page,
        username=account,
        expected_dialog_url="/admin/player/withdraw",
    )
    dialog = get_dialog_frame(page, "/admin/player/withdraw")
    dialog_balance = read_dialog_money(dialog, ('input[name="score"]', 'input[name="player_balance"]'))
    if dialog_balance is not None:
        balance_before = dialog_balance
    fill_amount(dialog.locator('input[name="balance"]').first, amount)
    dialog.locator('button.layui-btn[lay-filter="withdraw"]').first.click()
    try:
        wait_for_action_success(page)
    except ActionFailed as e:
        if re.search(r"insufficient|not enough", str(e), re.IGNORECASE):
            raise ActionFailed("PLAYER_INSUFFICIENT_FUNDS", str(e)) from e
        raise
    dismiss_layui_popups(page)
    post = search_player(page, account)
    balance_after = read_row_balance(post)
    dismiss_layui_popups(page)
    agent_balance_after = read_agent_balance(page)
    send_cashout_report(account, amount, balance_after, agent_balance_after)
    return {
        "status": "success",
        "action": "redeem",
        "player": account,
        "amount": amount,
        "balance_before": balance_before,
        "balance_after": balance_after,
        "agent_balance_after": agent_balance_after,
    }


def create_player(page: Page, account: str, password: str) -> dict:
    dismiss_layui_popups(page)
    disable_header_interception(page)
    open_user_management_tab(page)

    # Pre-existence check: search for the account BEFORE submitting create.
    # If it already exists, raise ACCOUNT_EXISTS deterministically — no need
    # to depend on post-submit toast timing (which can miss brief flash toasts).
    try:
        existing = search_player(page, account)
        if existing is not None:
            raise ActionFailed("ACCOUNT_EXISTS", f"Account {account!r} already exists")
    except PlayerNotFound:
        pass  # Good — account does not exist yet, proceed to create.

    um = get_user_management_frame(page)
    um.locator('button.layui-btn-sm[lay-event="add"]').first.click()
    dialog = get_dialog_frame(page, "/admin/player/insert")
    dialog.locator('input[name="username"]').fill(account)
    dialog.locator('input[name="nickname"]').fill(account)
    dialog.locator('input[name="money"]').fill("0")
    dialog.locator('input[id="password"]').fill(password)
    dialog.locator('input[name="password_confirmation"]').fill(password)
    dialog.locator('button.layui-btn[lay-submit][lay-filter="add"]').first.click()
    
    server_msg = None
    try:
        wait_for_action_success(page)
    except ActionFailed as e:
        if re.search(r"exists|already", str(e), re.IGNORECASE):
            raise ActionFailed("ACCOUNT_EXISTS", str(e)) from e
        server_msg = str(e)
    except TimeoutError:
        pass

    dismiss_layui_popups(page)
    page.wait_for_timeout(1500)
    found = None
    try:
        found = search_player(page, account)
    except PlayerNotFound:
        pass

    popup_lower = (server_msg or "").lower()
    if "exists" in popup_lower or "already" in popup_lower:
        raise ActionFailed("ACCOUNT_EXISTS", server_msg or "Account already exists")
    if found is not None:
        log(f"create_player: verified {account!r} exists via search")
        return {"status": "success", "action": "create", "created": True, "account": account}
    if server_msg:
        raise ActionFailed("VALIDATION_REJECTED", server_msg)
    raise ActionFailed("CREATE_FAILED", f"Create submit completed but player {account!r} not found via search")


def reset_password(page: Page, account: str, new_password: str) -> dict:
    dismiss_layui_popups(page)
    disable_header_interception(page)
    row = search_player(page, account)
    click_row_action(
        row,
        "reset_password",
        "Reset",
        page=page,
        username=account,
        expected_dialog_url="/admin/player/resetpw",
    )
    dialog = get_dialog_frame(page, "/admin/player/resetpw")
    dialog.locator('input[id="password"][name="password"]').fill(new_password)
    dialog.locator('input[name="password_confirmation"]').fill(new_password)
    dialog.locator('button.layui-btn[lay-submit][lay-filter="changePwd"]').first.click()
    try:
        wait_for_action_success(page)
    except ActionFailed as e:
        msg = str(e).lower()
        if "must contain" in msg or "must be" in msg or "between" in msg or "invalid" in msg:
            raise ActionFailed("PASSWORD_INVALID", str(e)) from e
        raise
    dismiss_layui_popups(page)
    return {"status": "success", "action": "reset", "reset": True, "account": account}


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Cash Machine automation")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("login", help="Log in and confirm dashboard is reachable")

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


def validate_env(action: str) -> list[str]:
    missing = []
    keys = ["ADSPOWER_API_KEY", "ADSPOWER_PROFILE_ID", "TELEGRAM_BOT_TOKEN", "CASH_MACHINE_USER", "CASH_MACHINE_PASS", "CAPTCHA_GROUP_ID"]
    for key in keys:
        if not os.getenv(key):
            missing.append(key)
    return missing


def main() -> None:
    args = build_parser().parse_args()

    missing = validate_env(args.cmd)
    if missing:
        fail(args.cmd, "MISSING_ENV", f"Set these in .env: {', '.join(missing)}")

    ws_url = None
    page = None
    started_by_us = False
    reused_profile = False
    try:
        if ADSPOWER_REUSE_IF_OPEN:
            ws_url = adspower_status(ADSPOWER_PROFILE_ID)
            if ws_url:
                reused_profile = True
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

            if reused_profile:
                try:
                    page.goto(CASH_MACHINE_DASHBOARD_URL, wait_until="domcontentloaded", timeout=30000)
                    page.reload(wait_until="domcontentloaded", timeout=15000)
                    page.wait_for_timeout(1000)
                    dismiss_layui_popups(page)
                except Exception as e:
                    log(f"Refresh-on-reuse ignored before login check: {e}")

            if not login_cash_machine(page):
                screenshot = _save_screenshot(page, "login_failed")
                fail(args.cmd, "LOGIN_FAILED", "Could not reach dashboard", screenshot)

            if args.cmd == "login":
                emit({"status": "success", "action": "login"})
                return

            if args.cmd == "balance":
                emit(get_balance(page, args.player))
                return

            if args.cmd == "recharge":
                emit(recharge_player(page, args.player, args.amount))
                return

            if args.cmd == "redeem":
                emit(redeem_player(page, args.player, args.amount))
                return

            if args.cmd == "create":
                emit(create_player(page, args.account, args.password))
                return

            if args.cmd == "reset":
                emit(reset_password(page, args.player, args.password))
                return
    except PlayerNotFound as e:
        screenshot = _save_screenshot(page, args.cmd)
        fail(args.cmd, "PLAYER_NOT_FOUND", f"Player {e} not found", screenshot)
    except ActionFailed as e:
        screenshot = _save_screenshot(page, args.cmd)
        fail(args.cmd, e.code, str(e), screenshot)
    except TimeoutError as e:
        screenshot = _save_screenshot(page, args.cmd)
        fail(args.cmd, "TIMEOUT", str(e), screenshot)
    except PlaywrightTimeout as e:
        screenshot = _save_screenshot(page, args.cmd)
        fail(args.cmd, "PAGE_TIMEOUT", str(e), screenshot)
    except RuntimeError as e:
        screenshot = _save_screenshot(page, args.cmd)
        msg = str(e)
        if "AGENT_FUNDS_EXHAUSTED" in msg:
            fail(args.cmd, "AGENT_FUNDS_EXHAUSTED", msg, screenshot)
        fail(args.cmd, "RUNTIME", msg, screenshot)
    except Exception as e:
        screenshot = _save_screenshot(page, args.cmd)
        fail(args.cmd, "UNEXPECTED", f"{type(e).__name__}: {e}", screenshot)
    finally:
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
