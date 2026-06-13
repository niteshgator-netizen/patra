# PATRA RESPONSIVE FIX — WORK LOG

> **ROLLBACK HASH (clean tree before any change):** `20ee1ac4acc04eab6cca0ec365b436cd999055d2`
> To undo everything: `git reset --hard 20ee1ac4acc04eab6cca0ec365b436cd999055d2`
> Branch: `main`. Committed per phase (`patra-responsive:`), **never pushed**.

---

## PHASE 0 — DIAGNOSIS (read-only, root cause per symptom)

### The shell (shared by everything)
`app/javascript/dashboard/routes/dashboard/Dashboard.vue` line 237-239 is the main panel that
holds every routed page:

```html
<main class="pat-dashboard-main flex flex-1 h-full w-full min-h-0 px-0 overflow-hidden">
  <router-view />
```

- It is a **flex row**, fixed full height, **`overflow-hidden`**.
- `NextSidebar` (the left nav) is its sibling — width is **user-resizable, default 200px, max 320px,
  `md:flex-shrink-0`** (`components-next/sidebar/provider.js` `DEFAULT_WIDTH=200, MAX_WIDTH=320`;
  `components-next/sidebar/Sidebar.vue:784,793`). It never shrinks.
- Consequence: a routed page only scrolls if **the page itself** sets `overflow-y:auto` on a
  height-bounded box. If it doesn't, `<main>`'s `overflow-hidden` silently **clips** the overflow.
  This single fact explains symptoms 4/5/6.

---

### Symptom 1 — opening the contact sidebar hides the chat/message list (laptop width)
**Files:**
- `routes/dashboard/conversation/ConversationView.vue:197-221` — the 3-column `<section class="flex w-full h-full min-w-0">`.
- `components/widgets/conversation/ConversationSidebar.vue:78` — the contact sidebar wrapper.
- `components/ChatList.vue:956-961` — the chat-list column.
- `components/widgets/conversation/ConversationBox.vue:94` — the messages column.

**The three columns inside the section:**
| Column | Class | Width behavior |
|---|---|---|
| ChatList | `w-[340px] 2xl:w-[412px]` + `flex-shrink-0` | **locked 340px**, never shrinks |
| ConversationBox (messages) | `w-full min-w-0` | the **only** flexible column — absorbs all squeeze, can shrink to 0 |
| ConversationSidebar | `xl:static xl:w-[360px] xl:min-w-[360px]` | at ≥1280px becomes a **locked 360px in-flow column** |

**Root cause:** at `xl` (≥1280px) the contact sidebar stops being an overlay and becomes a **static
360px column**. Now three width-locked boxes compete for the row: nav (200–320) + ChatList (340) +
contact sidebar (360) = up to **~1020px of fixed width**. Only the message column is flexible
(`min-w-0`), so it is the one that collapses. Message width ≈ `viewport − nav − 340 − 360`. On a
1280px-effective laptop (very common with Windows 125–150% display scaling) that is ~380px and
shrinks further as the nav is widened — the conversation gets crushed toward zero, reading as
"the message list disappeared."

The codebase **already** has the correct pattern below `xl`: `ConversationSidebar.vue:78` is
`fixed top-0 right-0 w-full max-w-sm … shadow-lg` — a slide-over **drawer** that overlays instead of
stealing width. The bug is purely that the **static-column threshold (`xl`=1280) is too low** for a
layout that also carries a 200px+ nav and a 340px chat list. → **Fix: push that threshold to `2xl`
(1536px)** so 1280–1535px laptops keep the drawer and never lose the messages.

### Symptom 2 — blocks/panels congested, cramped, overlapping on small screens
Primarily a **consequence of symptom 1** (message column crushed) plus uniform desktop padding
(`p-6` = 24px) used unchanged on phones. No separate overlap bug found beyond the column crush.
→ Addressed by the Phase 1 drawer fix + Phase 3 responsive padding.

### Symptom 3 — laggy on small screens
Found one concrete, fixable culprit: `ConversationSidebar.vue:42-48` `onSpotlightMove` writes
`el.style.left`/`el.style.top` on **every** `mousemove` (a document-level listener), and `#spotlight`
is `position:fixed; filter:blur(12px)` (`conversation-sidebar-patra.scss:49-66`). Uncoalesced
left/top writes to a blurred fixed layer = layout+paint thrash on every pointer move whenever a
conversation is open. The codebase already fixed the identical bug for the global spotlight in
`Dashboard.vue:80-101` (rAF-coalesced). This one was missed. → **Fix: rAF-coalesce it** (same pattern).
Any remaining "lag" beyond this is likely data-volume / device and needs real profiling — not a
blind layout guess.

### Symptoms 4 + 5 + 6 — report pages don't scroll / aren't responsive
**Files & exact offending lines:**
- `routes/dashboard/reports/SweepsReport.vue:79` — root `<div class="flex flex-col gap-4 p-6 sw-page">`.
  **No `overflow-y`, no bounded height.** Inside `<main overflow-hidden>` → lower rows clipped, no scroll.
  This is the **"Sweeps Financial"** page (the `patra_sweeps_report` route the Reports-hub card points to).
- `routes/dashboard/patra/PatraReports.vue:100` + style `:511-525` — root `.pat-page-wrap` has
  `min-height:100%` and **no `overflow-y`**. Same clip. (This is the `/patra/reports` "Sweepstakes
  Reports" page.) Also has `margin-left/right:-24px` (edge-bleed) which must be respected by the fix.
- **Contrast / proof:** `routes/dashboard/patra/PatraReportsHub.vue:119` root **does** have
  `overflow-y-auto` and scrolls fine — confirming the missing-`overflow-y` diagnosis above.

**Responsiveness:** the stat/KPI grids are already fluid
(`SweepsReport` `.sw-kpis` = `repeat(auto-fit,minmax(150px,1fr))`; `PatraReports` uses
`grid-cols-2 md:grid-cols-3/4`). The remaining gap is **wide tables on narrow screens** — they need a
horizontal-scroll wrapper so cells aren't cut off.

**Root cause (4/5/6):** pages rely on a parent to scroll, but the parent (`<main>`) is
`overflow-hidden`. The page must own its scroll. → **Fix: give each report page a bounded,
`overflow-y:auto` scroll container (matching PatraReportsHub) + wrap tables in `overflow-x:auto`.**

---
