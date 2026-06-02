#!/usr/bin/env python3
"""Apply pat-page-wrap dark Patra styling to unstyled Vue pages."""
from __future__ import annotations

import glob
import os
import re
import sys

REPO = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASE = os.path.join(REPO, "app", "javascript", "dashboard")

STYLED_RE = re.compile(
    r"#050409|pat-page-wrap|pat-list-wrap|pat-reports-wrap|pat-overview-wrap|var\(--canvas\)"
)

PATRA_STYLE = """
.pat-page-wrap {
  --canvas: #050409;
  --surface: #0c0b12;
  --surface-2: #131119;
  --surface-3: #1b1925;
  --surface-4: #252233;
  --border: #171520;
  --border-hi: #2e2940;
  --patra: #6e56cf;
  --patra-3: #a78bfa;
  --text: #ededf2;
  --text-2: #a8a6b6;
  --text-3: #75727f;
  --text-4: #54515e;
  --green: #3fb950;
  --red: #f85149;

  position: relative;
  min-height: 100%;
  margin-left: -24px;
  margin-right: -24px;
  padding: 0 24px 24px;
  color: var(--text);
  font-family: 'Inter', sans-serif;
  background: var(--canvas);
}

.pat-page-main {
  position: relative;
  z-index: 1;
}

.pat-page-wrap :deep(.text-heading-1),
.pat-page-wrap :deep(h1),
.pat-page-wrap :deep(h2) {
  color: var(--text) !important;
}

.pat-page-wrap :deep(.text-n-slate-12) {
  color: var(--text) !important;
}

.pat-page-wrap :deep(.text-n-slate-11) {
  color: var(--text-2) !important;
}

.pat-page-wrap :deep(.text-n-slate-10),
.pat-page-wrap :deep(.text-n-slate-9) {
  color: var(--text-3) !important;
}

.pat-page-wrap :deep(.text-n-slate-6),
.pat-page-wrap :deep(.text-n-slate-7),
.pat-page-wrap :deep(.text-n-slate-8) {
  color: var(--text-4) !important;
}

.pat-page-wrap :deep(.bg-n-surface-1),
.pat-page-wrap :deep(.bg-n-solid-1) {
  background: var(--canvas) !important;
}

.pat-page-wrap :deep(.bg-n-surface-2),
.pat-page-wrap :deep(.bg-n-solid-2),
.pat-page-wrap :deep(.bg-n-solid-3) {
  background: var(--surface) !important;
}

.pat-page-wrap :deep(.bg-n-alpha-1),
.pat-page-wrap :deep(.bg-n-alpha-2) {
  background: var(--surface-2) !important;
}

.pat-page-wrap :deep(.bg-n-slate-1),
.pat-page-wrap :deep(.bg-n-slate-2) {
  background: var(--surface-2) !important;
}

.pat-page-wrap :deep(.bg-n-slate-3) {
  background: var(--surface-3) !important;
}

.pat-page-wrap :deep(.rounded-xl.border),
.pat-page-wrap :deep(.rounded-lg.border) {
  border-color: var(--border) !important;
}

.pat-page-wrap :deep(.border-n-weak),
.pat-page-wrap :deep(.border-n-container),
.pat-page-wrap :deep(.outline-n-weak),
.pat-page-wrap :deep(.outline-n-container),
.pat-page-wrap :deep(.dark\\:border-n-slate-6) {
  border-color: var(--border) !important;
  outline-color: var(--border) !important;
}

.pat-page-wrap :deep(.divide-y > *) {
  border-color: var(--border) !important;
}

.pat-page-wrap :deep(.group-hover\\:bg-n-alpha-2) {
  background: var(--surface-2) !important;
  border-color: var(--border-hi) !important;
  color: var(--text-2) !important;
}

.pat-page-wrap :deep(.group:hover .group-hover\\:bg-n-alpha-2) {
  background: var(--surface-3) !important;
  border-color: var(--patra) !important;
  color: var(--text) !important;
}

.pat-page-wrap :deep(thead) {
  background: var(--surface-2) !important;
}

.pat-page-wrap :deep(thead th) {
  color: var(--text-4) !important;
  border-bottom: 1px solid var(--border);
}

.pat-page-wrap :deep(tbody tr:hover) {
  background: var(--surface-2) !important;
}

.pat-page-wrap :deep(tbody td) {
  color: var(--text);
  border-color: var(--border);
}

.pat-page-wrap :deep(input),
.pat-page-wrap :deep(textarea),
.pat-page-wrap :deep(select) {
  background: var(--surface-2);
  border: 1px solid var(--border);
  color: var(--text);
  border-radius: 8px;
}

.pat-page-wrap :deep(input:focus),
.pat-page-wrap :deep(textarea:focus),
.pat-page-wrap :deep(select:focus) {
  border-color: var(--patra);
  outline: none;
  box-shadow: 0 0 0 3px rgba(110, 86, 207, 0.11);
}

.pat-page-wrap :deep(.text-n-teal-10),
.pat-page-wrap :deep(.text-n-teal-11) {
  color: var(--green) !important;
}

.pat-page-wrap :deep(.text-n-ruby-9),
.pat-page-wrap :deep(.text-n-ruby-10) {
  color: var(--red) !important;
}

.pat-page-wrap :deep(.fixed.z-50.bg-n-slate-12) {
  background: var(--surface-4) !important;
  border: 1px solid var(--border-hi);
  color: var(--text) !important;
}

.pat-page-wrap :deep(.animate-loader-pulse) {
  background: var(--surface-3) !important;
}
"""

WRAPPER_STYLE = """
.pat-settings-shell {
  --canvas: #050409;
  --surface: #0c0b12;
  --border: #171520;
  --text: #ededf2;
  --text-2: #a8a6b6;
  background: var(--canvas) !important;
  color: var(--text);
}

.pat-settings-shell :deep(.bg-n-surface-1),
.pat-settings-shell :deep(.bg-n-solid-1) {
  background: var(--canvas) !important;
}

.pat-settings-shell :deep(.text-n-slate-12) {
  color: var(--text) !important;
}

.pat-settings-shell :deep(.text-n-slate-11) {
  color: var(--text-2) !important;
}

.pat-settings-shell :deep(.border-n-weak) {
  border-color: var(--border) !important;
}
"""

SECTIONS: dict[str, list[str]] = {
    "A": [
        "routes/dashboard/campaigns/pages/LiveChatCampaignsPage.vue",
        "routes/dashboard/campaigns/pages/SMSCampaignsPage.vue",
        "routes/dashboard/campaigns/pages/WhatsAppCampaignsPage.vue",
    ],
    "B": [
        "routes/dashboard/settings/profile/Index.vue",
        "routes/dashboard/settings/profile/MfaSettings.vue",
    ],
    "C": [
        "routes/dashboard/companies/pages/CompaniesIndex.vue",
        "routes/dashboard/companies/pages/CompanyDetailView.vue",
    ],
    "D": ["modules/search/components/SearchView.vue"],
    "E": ["routes/dashboard/notifications/components/NotificationsView.vue"],
    "F": [
        "routes/dashboard/onboarding/Index.vue",
        "routes/dashboard/suspended/Index.vue",
        "routes/dashboard/noAccounts/Index.vue",
    ],
    "G": [
        "routes/dashboard/settings/inbox/ChannelList.vue",
        "routes/dashboard/settings/inbox/FinishSetup.vue",
        "routes/dashboard/settings/inbox/ChannelFactory.vue",
        "routes/dashboard/settings/inbox/AddAgents.vue",
        "routes/dashboard/settings/inbox/Settings.vue",
        "routes/dashboard/settings/teams/Create/CreateTeam.vue",
        "routes/dashboard/settings/teams/FinishSetup.vue",
        "routes/dashboard/settings/teams/Create/AddAgents.vue",
        "routes/dashboard/settings/teams/Edit/EditTeam.vue",
        "routes/dashboard/settings/teams/Edit/EditAgents.vue",
        "routes/dashboard/settings/macros/Index.vue",
        "routes/dashboard/settings/macros/MacroEditor.vue",
        "routes/dashboard/settings/attributes/Index.vue",
        "routes/dashboard/settings/agentBots/Index.vue",
        "routes/dashboard/settings/auditlogs/Index.vue",
        "routes/dashboard/settings/billing/Index.vue",
        "routes/dashboard/settings/captain/Index.vue",
        "routes/dashboard/settings/conversationWorkflow/index.vue",
        "routes/dashboard/settings/customRoles/Index.vue",
        "routes/dashboard/settings/sla/Index.vue",
        "routes/dashboard/settings/security/Index.vue",
        "routes/dashboard/settings/metaApp/MetaAppSettings.vue",
        "routes/dashboard/settings/integrations/Index.vue",
        "routes/dashboard/settings/integrations/DashboardApps/Index.vue",
        "routes/dashboard/settings/integrations/Webhooks/Index.vue",
        "routes/dashboard/settings/integrations/Slack.vue",
        "routes/dashboard/settings/integrations/Linear.vue",
        "routes/dashboard/settings/integrations/Notion.vue",
        "routes/dashboard/settings/integrations/Shopify.vue",
        "routes/dashboard/settings/integrations/IntegrationHooks.vue",
    ],
    "H": [
        "routes/dashboard/settings/assignmentPolicy/Index.vue",
        "routes/dashboard/settings/assignmentPolicy/pages/AgentAssignmentIndexPage.vue",
        "routes/dashboard/settings/assignmentPolicy/pages/AgentAssignmentCreatePage.vue",
        "routes/dashboard/settings/assignmentPolicy/pages/AgentAssignmentEditPage.vue",
        "routes/dashboard/settings/assignmentPolicy/pages/AgentCapacityIndexPage.vue",
        "routes/dashboard/settings/assignmentPolicy/pages/AgentCapacityCreatePage.vue",
        "routes/dashboard/settings/assignmentPolicy/pages/AgentCapacityEditPage.vue",
    ],
    "I": [
        "routes/dashboard/patra/PatraAddChannel.vue",
        "routes/dashboard/patra/PatraReports.vue",
        "routes/dashboard/settings/knowledge/KnowledgeBase.vue",
        "routes/dashboard/settings/attributes/CustomAttributesBuilder.vue",
    ],
    "J": [
        "routes/dashboard/broadcasts/BroadcastList.vue",
        "routes/dashboard/broadcasts/BroadcastComposer.vue",
    ],
    "K": [
        "routes/dashboard/settings/automation/FlowList.vue",
        "routes/dashboard/settings/automation/FlowBuilder.vue",
    ],
    "N": [
        "routes/dashboard/settings/SettingsWrapper.vue",
        "routes/dashboard/settings/Wrapper.vue",
    ],
}


def collect_helpcenter_pages() -> list[str]:
    paths: list[str] = []
    for pattern in (
        "routes/dashboard/helpcenter/pages/**/*.vue",
        "routes/dashboard/helpcenter/components/**/*.vue",
    ):
        for f in glob.glob(os.path.join(BASE, pattern), recursive=True):
            rel = os.path.relpath(f, BASE).replace("\\", "/")
            paths.append(rel)
    return sorted(set(paths))


def collect_captain_pages() -> list[str]:
    paths: list[str] = []
    for f in glob.glob(
        os.path.join(BASE, "routes/dashboard/captain/**/*.vue"), recursive=True
    ):
        rel = os.path.relpath(f, BASE).replace("\\", "/")
        paths.append(rel)
    return sorted(set(paths))


def is_styled(content: str) -> bool:
    return bool(STYLED_RE.search(content))


def wrap_template(content: str) -> str:
    if "pat-page-wrap" in content or "pat-settings-shell" in content:
        return content

    root_match = re.search(r"<template>\s*\n?", content)
    if not root_match:
        return content

    inner_start = root_match.end()
    style_match = re.search(r"<style(?:\s|>)", content[inner_start:])
    search_end = inner_start + style_match.start() if style_match else len(content)
    last_close = content.rfind("</template>", inner_start, search_end)
    if last_close == -1:
        return content

    inner = content[inner_start:last_close]
    if not inner.strip():
        return content

    first_line = next((line for line in inner.split("\n") if line.strip()), "")
    base_indent = re.match(r"^(\s*)", first_line).group(1) if first_line else "  "
    main_indent = base_indent + "  "

    wrapped = (
        f'{base_indent}<div class="pat-page-wrap">\n'
        f'{main_indent}<div class="pat-page-main">\n'
        f"{inner.rstrip()}\n"
        f"{main_indent}</div>\n"
        f'{base_indent}</div>'
    )

    return content[:inner_start] + wrapped + content[last_close:]


def add_style_block(content: str, style_block: str, marker: str) -> str:
    if marker in content:
        return content

    style_re = re.search(r"<style scoped>([\s\S]*?)</style>", content)
    if style_re:
        insert_at = style_re.end(1)
        return content[:insert_at] + style_block + content[insert_at:]

    return content.rstrip() + f"\n\n<style scoped>{style_block}\n</style>\n"


def style_settings_wrapper(content: str) -> str:
    if "pat-settings-shell" in content:
        return add_style_block(content, WRAPPER_STYLE, ".pat-settings-shell")

    content = content.replace("bg-n-surface-1 ", "").replace(" bg-n-surface-1", "")
    content = re.sub(
        r'(<div\s+class=")(flex flex-col w-full h-full)',
        r'\1pat-settings-shell \2',
        content,
        count=1,
    )
    content = re.sub(
        r'(<div\s+class=")(flex flex-col h-full m-0)',
        r'\1pat-settings-shell \2',
        content,
        count=1,
    )
    return add_style_block(content, WRAPPER_STYLE, ".pat-settings-shell")


def process_file(rel_path: str, is_wrapper: bool = False) -> tuple[str, str]:
    """Returns (status, reason) where status is changed|skipped|missing."""
    full = os.path.join(BASE, rel_path)
    if not os.path.isfile(full):
        return "missing", "not found"

    with open(full, encoding="utf-8") as f:
        content = f.read()

    if is_styled(content):
        return "skipped", "already styled"

    original = content
    if is_wrapper:
        content = style_settings_wrapper(content)
    else:
        content = wrap_template(content)
        content = add_style_block(content, PATRA_STYLE, ".pat-page-wrap")

    if content == original:
        return "skipped", "no changes applied"

    with open(full, "w", encoding="utf-8") as f:
        f.write(content)
    return "changed", ""


def main() -> int:
    os.chdir(REPO)
    changed: dict[str, list[str]] = {}
    skipped: list[tuple[str, str]] = []
    missing: list[str] = []

    all_sections = dict(SECTIONS)
    all_sections["L"] = collect_helpcenter_pages()
    all_sections["M"] = collect_captain_pages()

    for section, files in all_sections.items():
        for rel in files:
            is_wrapper = rel.endswith("SettingsWrapper.vue") or rel.endswith(
                "settings/Wrapper.vue"
            )
            status, reason = process_file(rel, is_wrapper=is_wrapper)
            if status == "changed":
                changed.setdefault(section, []).append(rel)
            elif status == "skipped":
                skipped.append((rel, reason))
            else:
                missing.append(rel)

    print("=== CHANGED ===")
    total = 0
    for section in sorted(changed.keys()):
        print(f"\n[{section}]")
        for f in changed[section]:
            print(f"  {f}")
            total += 1
    print(f"\nTOTAL CHANGED: {total}")

    print("\n=== SKIPPED ===")
    for f, reason in skipped:
        print(f"  {f} — {reason}")

    print("\n=== MISSING ===")
    for f in missing:
        print(f"  {f}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
