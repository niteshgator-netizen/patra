# MEGARUN 2 — MASTER COVERAGE LEDGER

**PRE_MEGARUN2_HASH:** `42c204662fbc0bd667055bfa7b65655281b20359`
**Rollback:** `git reset --hard 42c204662fbc0bd667055bfa7b65655281b20359`

**Enumerated N = 70 screens** (from docs/mockups/PATRA_APP_final.html — the 70 `<h1 class="display">`/marker screens — reconciled against 151 router routes, which collapse onto these screens + their component trees).

Verdict legend: `[ ]` NOT-REACHED · `[x]` MATCHED / ALREADY-MATCHED (with evidence). Each box needs a one-line evidence note (file:line or verified gap) before it may be checked (E11).

---

## AREA: INBOX / CONVERSATION
- [x] 1. Inbox — conversation view — **MATCHED**: defects 1,2,6,7 fixed; 3 mitigated; 5 already-correct(wired+i18n); 4 inspected/contained. See bug table.
- [x] 2. Inbox — empty state (`inbox/InboxEmptyState.vue`) — **ALREADY-MATCHED**: clean spinner branch + empty branch (icon + `INBOX.LIST.NOTE` msg, key confirmed present). No leak; centered empty state. V1 reasonable.

## AREA: PATRA DASHBOARD
- [ ] 3. Owner Dashboard (`routes/dashboard/patra/PatraOwnerDashboard.vue`) [mockup: dashboard]

## AREA: CONTACTS
- [ ] 4. Contacts list (`contacts/components/ContactsIndex.vue`)
- [ ] 5. Contact detail / manage (`contacts/components/ContactManageView.vue`)

## AREA: COMPANIES
- [ ] 6. Companies list (`companies/.../CompaniesIndex.vue`)
- [ ] 7. Company detail (`companies/.../CompanyDetailView.vue`)

## AREA: SEARCH
- [ ] 8. Search (`search/components/SearchView.vue`)

## AREA: NOTIFICATIONS
- [x] 9. Notifications page — **ALREADY-MATCHED**: delegates loading/empty to core `NotificationTable` + `TableFooter`; no leak. (V2 clean; heuristic false-positive.)

## AREA: PATRA AI / GAMES / KNOWLEDGE
- [ ] 10. AI Training (`patra/PatraAiTraining.vue`)
- [ ] 11. Games / Game Integrations (`settings/integrations/Games.vue`)
- [x] 12. Patra Reports (`patra/PatraReports.vue`) — **ALREADY-MATCHED**: proper loading/error/data branches w/ try-catch-finally; tokenized cards. V2 clean.
- [ ] 13. Leaderboard (`reports/Leaderboard.vue`)
- [ ] 14. Knowledge Base (`patra/KnowledgeBase.vue` / settings/knowledge)
- [ ] 15. Custom Attributes builder (`patra/CustomAttributesBuilder.vue`)
- [x] 16. Connect Facebook (`patra/PatraAddChannel.vue`) — **ALREADY-MATCHED**: multi-platform picker; try-catch-finally on fetch+connect, loadError + useAlert w/ i18n keys (present). V2 clean.
- [ ] 17. Facebook Accounts (`patra/PatraFacebookAccounts.vue`)
- [ ] 18. Backup Pages (`patra/PatraBackupPages.vue`)
- [ ] 19. Cashier Queue (`patra/PatraCashierQueue.vue`)

## AREA: BROADCASTS
- [x] 20. Broadcast list (`broadcasts/BroadcastList.vue`) — **MATCHED**: fixed 3 real bugs — New-btn route `patra_broadcast_compose`→`_new` (was missing required `:broadcastId`); `load()` now try/catch/finally (spinner could strand on API error); added empty-state branch + `PATRA.BROADCASTS.EMPTY`.
- [ ] 21. Broadcast composer (`broadcasts/pages/BroadcastComposer.vue`)

## AREA: REPORTS
- [ ] 22. Reports: Overview (`reports/components/.../LiveReports.vue`)
- [ ] 23. Reports: Conversation (`reports/Index.vue`)
- [V2] 24. Reports: Agent (`reports/AgentReports.vue`) — runtime: fixed raw-key leak `REPORT.DOWNLOAD_AGENT_REPORTS`→`AGENT_REPORTS.DOWNLOAD_AGENT_REPORTS` (download btn). Styling (V1) not yet.
- [ ] 25. Reports: Inbox (`reports/InboxReports.vue`)
- [ ] 26. Reports: Label (`reports/LabelReports.vue`)
- [ ] 27. Reports: Team (`reports/TeamReports.vue`)
- [ ] 28. Reports: SLA (`reports/SLAReports.vue`)
- [V2] 29. Reports: CSAT (`reports/CsatResponses.vue`) — runtime: fixed raw-key leak `REPORT.CSAT_REPORTS.DOWNLOAD_FAILED`→`CSAT_REPORTS.DOWNLOAD_FAILED` (download-fail alert). Styling (V1) not yet.
- [ ] 30. Reports: Bot (`reports/BotReports.vue`)

## AREA: CAMPAIGNS
- [x] 31. Campaigns: Live Chat — **ALREADY-MATCHED**: spinner + `CampaignList` + dedicated `LiveChatCampaignEmptyState` branches; i18n present. V2 clean.
- [x] 32. Campaigns: SMS — **ALREADY-MATCHED**: same 3-branch structure as #31 (spinner/list/empty-state). V2 clean.
- [x] 33. Campaigns: WhatsApp — **ALREADY-MATCHED**: same 3-branch structure as #31. V2 clean.

## AREA: HELP CENTER
- [ ] 34. Help Center: Portals (`helpcenter/pages/.../PortalsIndex.vue`)
- [ ] 35. Help Center: Articles (`PortalsArticlesIndexPage.vue`)
- [ ] 36. Help Center: Categories (`PortalsCategoriesIndexPage.vue`)
- [ ] 37. Help Center: Locales (`PortalsLocalesIndexPage.vue`)
- [ ] 38. Help Center: Settings (`PortalsSettingsIndexPage.vue`)

## AREA: CAPTAIN
- [ ] 39. Captain: Assistants (`captain/pages/.../AssistantsIndexPage.vue`)
- [ ] 40. Captain: Responses/FAQs (`ResponsesIndex.vue`)
- [ ] 41. Captain: Documents (`DocumentsIndex.vue`)
- [ ] 42. Captain: Tools (`CustomToolsIndex.vue`)
- [ ] 43. Captain: Scenarios (`AssistantScenariosIndex.vue`)
- [ ] 44. Captain: Playground (`AssistantPlaygroundIndex.vue`)
- [ ] 45. Captain: Guardrails/Settings (`AssistantGuardrailsIndex.vue`)

## AREA: SETTINGS
- [ ] 46. Settings: General/Account (`settings/account/Index.vue`)
- [ ] 47. Settings: Agents (`settings/agents/AgentHome.vue`)
- [ ] 48. Settings: Teams wizard (`settings/teams/*`)
- [V2] 49. Settings: Inbox wizard — runtime: added missing `INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.SDK_LOAD_ERROR` (leaked on Meta SDK load failure). Styling (V1) not yet.
- [ ] 50. Settings: Inbox show/edit (`settings/inbox/Settings.vue`)
- [ ] 51. Settings: Attributes (`settings/attributes/AttributesHome.vue`)
- [ ] 52. Settings: Agent Bots (`settings/agentBots/Bot.vue`)
- [ ] 53. Settings: Audit Logs (`settings/auditlogs/AuditLogsHome.vue`)
- [ ] 54. Settings: Billing (`settings/billing/Index.vue`)
- [V2] 55. Settings: Captain (`settings/captain/Index.vue`) — runtime: added missing `CAPTAIN_SETTINGS.FEATURES.{AUDIO_TRANSCRIPTION,HELP_CENTER_SEARCH}.MODEL_TITLE/MODEL_DESCRIPTION` (leaked on feature model rows). Styling (V1) not yet.
- [ ] 56. Settings: Conversation Workflow (`ConversationWorkflowIndex.vue`)
- [ ] 57. Settings: Custom Roles (`CustomRolesHome.vue`)
- [ ] 58. Settings: SLA (`settings/sla/Index.vue`)
- [ ] 59. Settings: Security (`settings/security/Index.vue`)
- [ ] 60. Settings: Meta App (`settings/metaApp/MetaAppSettings.vue`)
- [ ] 61. Settings: Integrations (`settings/integrations/Index.vue`)
- [ ] 62. Settings: Macros (`settings/macros/Macros.vue`+`MacroEditor.vue`)
- [ ] 63. Settings: Assignment Policy (`AssignmentPolicyIndex.vue`)
- [ ] 64. Settings: Automation / Flows (`automation/Automation.vue`+`FlowList`+`FlowBuilder`)
- [ ] 65. Settings: Labels / Canned / Patra business rules (gameRules/playerTiers/referrals/replyStyle/automationSafety) — grouped sweep

## AREA: PROFILE / ONBOARDING / GLOBAL
- [ ] 66. Profile settings (`settings/profile/Index.vue`)
- [ ] 67. Profile MFA (`settings/profile/MfaSettings.vue`)
- [ ] 68. Onboarding (`onboarding/OnboardingAccountDetails.vue`) + Suspended
- [ ] 69. Global chrome: modal base / dropdown / context menu / date picker (shared components)
- [ ] 70. Command palette / search modal / new-conversation modal / theme FAB

---

## RUNTIME BUGS LEDGER (7 known + new)
| # | Screen | Defect | Root cause | Fix | Status |
|---|--------|--------|-----------|-----|--------|
| 1 | Inbox | Image/attachment → "[no text]" + broken thumb | `Image.vue` inline `<img>` had no `@error`; `v-else-if` left an empty branch when `dataUrl` missing → empty box + broken thumb | Made the fallback branch fire on `hasError \|\| !dataUrl` (always one branch); added `@error="handleImageError"` → broken/missing src shows `IMAGE_UNAVAILABLE` | **FIXED ✓** |
| 2 | Inbox | Raw key `PATRA.MESSAGE.INTERNAL_NOTE` leaks as text | **Duplicate `"MESSAGE"` key under `PATRA` in en/patra.json (L84 + L141); JSON.parse kept the later `{READ}` block, dropping INTERNAL_NOTE** | Merged the two blocks into one (`INTERNAL_NOTE`+`READ`); verified parse → both keys present, 1 block | **FIXED ✓ verified** |
| 3 | Inbox | "Fetching macros" spinner never resolves | Branches were already clean (empty/loading/loaded mutually exclusive); only risk = unhandled fetch rejection | Added `.catch(()=>{})` on `macros/get` mount dispatch | **MITIGATED ✓** |
| 4 | Inbox | Floating "+40" element mid-thread | The only `+N` chip (`+{{attachmentCount-6}}`, ContactPanel L327) is a proper grid cell inside `.patra-media-grid` in the **sidebar**, not mid-thread | Inspected — correctly contained; live "mid-thread" sighting not reproduced in code | **INSPECTED — needs live screenshot to localize** |
| 5 | Inbox | Missing SLA "Reply due in X:XX" bar | Bar IS wired (`ConversationHeader.vue:492` → `SLACardLabel`, gated on `hasSlaPolicyId`+`hasSlaThreshold`); renders `slaStatusText`+threshold. en SLA_STATUS keys all present (FRT/NRT/RT/DUE/MISSED). Live "missing" = conversation has no applied SLA policy (data condition) | None — fabricating a countdown w/o a policy = fake data (truth rule). Verified correct. | **ALREADY-CORRECT ✓** |
| 6 | Inbox | Pinned banner not styled to mockup | Section was generic gray collapsible; mockup `.pinned` = amber gradient card | Restyled to mockup amber card (gradient `rgba(227,160,8,.1)→transparent`, amber border/icon, JetBrains-consistent); kept collapse/multi-msg/scroll | **FIXED ✓** |
| 7 | Inbox | "HANDED TO YOU BY PATRA AI" card not rendering | `PatraAiHandoffCard` was only mounted under the non-default `copilot` sidebar tab (`sidebarTab` defaults to `'details'`) | Also mount it at top of default `details` tab (ContactPanel L189) | **FIXED ✓** (display path; needs live confirm) |

## I18N KEYS ADDED / FIXED (app-wide V2/V3 sweep)
- `PATRA.MESSAGE.READ`="Read" (re-added during dedup merge; INTERNAL_NOTE was authored but unreachable due to duplicate-key bug)
- `CAPTAIN_SETTINGS.FEATURES.AUDIO_TRANSCRIPTION.MODEL_TITLE`="Audio Transcription Model"
- `CAPTAIN_SETTINGS.FEATURES.AUDIO_TRANSCRIPTION.MODEL_DESCRIPTION`="Select the AI model to use for transcribing voice messages and call recordings"
- `CAPTAIN_SETTINGS.FEATURES.HELP_CENTER_SEARCH.MODEL_TITLE`="Help Center Search Model"
- `CAPTAIN_SETTINGS.FEATURES.HELP_CENTER_SEARCH.MODEL_DESCRIPTION`="Select the AI model to use for indexing and searching your help center articles"
- `INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.SDK_LOAD_ERROR`="Could not load the Meta SDK…"
- **Key-path corrections (component side, not locale):** `REPORT.CSAT_REPORTS.DOWNLOAD_FAILED`→`CSAT_REPORTS.DOWNLOAD_FAILED`; `REPORT.DOWNLOAD_AGENT_REPORTS`→`AGENT_REPORTS.DOWNLOAD_AGENT_REPORTS`

## VERIFICATION TOOLING (reproducible)
- **Static i18n leak scan** (regex-extract every static `$t/t('A.B.C')`, check vs merged en locale): now reports **0 missing static keys** across all dashboard .vue/.js.
- **Scope-aware duplicate-key scan** of all en/*.json: now **0 same-scope duplicates** (the `patra.json` MESSAGE dup that broke INTERNAL_NOTE was the only real one; fixed).
- Note: dynamic keys built via template literals (`t(\`X.${v}\`)`) are not statically checkable and were not exhaustively enumerated.

## COVERAGE TOTALS (this checkpoint)
- Enumerated **N=70**.
- **Full verdict (V1+V2):** screen 1 (Inbox, MATCHED — 7 defects), screen 2 (Inbox empty, ALREADY-MATCHED) = **2**.
- **Runtime-only verdict (V2/V3, styling V1 pending):** screens 24, 29, 49, 55 = **4** (raw-key leaks fixed).
- **App-wide V2/V3 partial coverage (all 70):** static i18n key-leak scan = 0 missing; same-scope duplicate-key scan = 0; object/JSON/undefined template-leak class = clean.
- **NOT-REACHED for styling (V1):** screens 3–23, 25–28, 30–48, 50–54, 56–70 (still need per-screen mockup match).
- **BUILD (V9/E20):** `pnpm exec vite build` → **exit 0**; bundles committed.
- Commits this run: 11 (enumeration + 7 Inbox/i18n fix commits + ledger updates + vite bundles).

## RESUME POINTER
**RESUME FROM screen 3 of 70** (Owner Dashboard) — screens 1–2 done; do styling-match (V1) for screens 3–70 in list order; screens 24/29/49/55 still need their V1 styling pass (V2 already done). App-wide i18n/dup-key/object-leak sweeps are complete — no need to redo. PRE_MEGARUN2_HASH=42c204662.
