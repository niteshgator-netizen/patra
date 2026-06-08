# MEGARUN 2 — MASTER COVERAGE LEDGER

**PRE_MEGARUN2_HASH:** `42c204662fbc0bd667055bfa7b65655281b20359`
**Rollback:** `git reset --hard 42c204662fbc0bd667055bfa7b65655281b20359`

**Enumerated N = 70 screens** (from docs/mockups/PATRA_APP_final.html — the 70 `<h1 class="display">`/marker screens — reconciled against 151 router routes, which collapse onto these screens + their component trees).

Verdict legend: `[ ]` NOT-REACHED · `[x]` MATCHED / ALREADY-MATCHED (with evidence). Each box needs a one-line evidence note (file:line or verified gap) before it may be checked (E11).

---

## AREA: INBOX / CONVERSATION
- [ ] 1. Inbox — conversation view (`routes/dashboard/conversation/ConversationView.vue` + ConversationBox/Message tree) — **fix 7 known defects first**
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
| 1 | Inbox | Image/attachment → "[no text]" + broken thumb | — | — | open |
| 2 | Inbox | Raw key `PATRA.MESSAGE.INTERNAL_NOTE` leaks | missing en string | — | open |
| 3 | Inbox | "Fetching macros" spinner never resolves | — | — | open |
| 4 | Inbox | Floating "+40" element mid-thread | — | — | open |
| 5 | Inbox | Missing SLA "Reply due in X:XX" bar | — | — | open |
| 6 | Inbox | Pinned banner not styled to mockup | — | — | open |
| 7 | Inbox | "HANDED TO YOU BY PATRA AI" card not rendering (`PatraAiHandoffCard.vue`) | — | — | open |

## I18N KEYS ADDED
(none yet)

## RESUME POINTER
RESUME FROM screen 1 of 70
