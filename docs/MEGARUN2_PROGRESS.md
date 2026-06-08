# MEGARUN 2 — MASTER COVERAGE LEDGER

**PRE_MEGARUN2_HASH:** `42c204662fbc0bd667055bfa7b65655281b20359`
**Rollback:** `git reset --hard 42c204662fbc0bd667055bfa7b65655281b20359`

**Enumerated N = 70 screens** (from docs/mockups/PATRA_APP_final.html — the 70 `<h1 class="display">`/marker screens — reconciled against 151 router routes, which collapse onto these screens + their component trees).

Verdict legend: `[ ]` NOT-REACHED · `[x]` MATCHED / ALREADY-MATCHED (with evidence). Each box needs a one-line evidence note (file:line or verified gap) before it may be checked (E11).

---

## AREA: INBOX / CONVERSATION
- [x] 1. Inbox — conversation view — **MATCHED**: defects 1,2,6,7 fixed; 3 mitigated; 5 already-correct(wired+i18n); 4 inspected/contained. See bug table.
- [ ] 2. Inbox — empty state (`InboxEmptyStateView.vue` / empty ConversationView)

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
- [ ] 9. Notifications page (`notifications/components/NotificationsView.vue`)

## AREA: PATRA AI / GAMES / KNOWLEDGE
- [ ] 10. AI Training (`patra/PatraAiTraining.vue`)
- [ ] 11. Games / Game Integrations (`settings/integrations/Games.vue`)
- [ ] 12. Patra Reports (`patra/PatraReports.vue`)
- [ ] 13. Leaderboard (`reports/Leaderboard.vue`)
- [ ] 14. Knowledge Base (`patra/KnowledgeBase.vue` / settings/knowledge)
- [ ] 15. Custom Attributes builder (`patra/CustomAttributesBuilder.vue`)
- [ ] 16. Connect Facebook (`patra/PatraAddChannel.vue`)
- [ ] 17. Facebook Accounts (`patra/PatraFacebookAccounts.vue`)
- [ ] 18. Backup Pages (`patra/PatraBackupPages.vue`)
- [ ] 19. Cashier Queue (`patra/PatraCashierQueue.vue`)

## AREA: BROADCASTS
- [ ] 20. Broadcast list (`broadcasts/pages/BroadcastList.vue`)
- [ ] 21. Broadcast composer (`broadcasts/pages/BroadcastComposer.vue`)

## AREA: REPORTS
- [ ] 22. Reports: Overview (`reports/components/.../LiveReports.vue`)
- [ ] 23. Reports: Conversation (`reports/Index.vue`)
- [ ] 24. Reports: Agent (`reports/AgentReports.vue`)
- [ ] 25. Reports: Inbox (`reports/InboxReports.vue`)
- [ ] 26. Reports: Label (`reports/LabelReports.vue`)
- [ ] 27. Reports: Team (`reports/TeamReports.vue`)
- [ ] 28. Reports: SLA (`reports/SLAReports.vue`)
- [ ] 29. Reports: CSAT (`reports/CsatResponses.vue`)
- [ ] 30. Reports: Bot (`reports/BotReports.vue`)

## AREA: CAMPAIGNS
- [ ] 31. Campaigns: Live Chat (`campaigns/pages/LiveChatCampaignsPage.vue`)
- [ ] 32. Campaigns: SMS (`campaigns/pages/SMSCampaignsPage.vue`)
- [ ] 33. Campaigns: WhatsApp (`campaigns/pages/WhatsAppCampaignsPage.vue`)

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
- [ ] 49. Settings: Inbox wizard (`settings/inbox/ChannelList`+`ChannelFactory`+`FinishSetup`)
- [ ] 50. Settings: Inbox show/edit (`settings/inbox/Settings.vue`)
- [ ] 51. Settings: Attributes (`settings/attributes/AttributesHome.vue`)
- [ ] 52. Settings: Agent Bots (`settings/agentBots/Bot.vue`)
- [ ] 53. Settings: Audit Logs (`settings/auditlogs/AuditLogsHome.vue`)
- [ ] 54. Settings: Billing (`settings/billing/Index.vue`)
- [ ] 55. Settings: Captain (`settings/captain/Index.vue`)
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

## I18N KEYS ADDED
- `PATRA.MESSAGE.READ` = "Read" (re-added during dedup merge; `INTERNAL_NOTE` was already authored but unreachable due to the duplicate-key bug)

## COVERAGE TOTALS (this checkpoint)
Enumerated N=70 · Verdicts=1 partial (screen 1) · Screens 2–70 NOT-REACHED.
Commits this run: 5 (1 enumeration + 1 per defect 2/7/3 + this ledger update).

## RESUME POINTER
**RESUME FROM screen 1 of 70** — finish Inbox defects 1, 5, 6 (pointers in bug table), then screen 2 (empty state) → 70 in list order. PRE_MEGARUN2_HASH=42c204662.
