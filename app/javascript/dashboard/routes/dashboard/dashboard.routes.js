import settings from './settings/settings.routes';
import conversation from './conversation/conversation.routes';
import { routes as searchRoutes } from '../../modules/search/search.routes';
import { routes as contactRoutes } from './contacts/routes';
import { routes as companyRoutes } from './companies/routes';
import { routes as notificationRoutes } from './notifications/routes';
import { routes as inboxRoutes } from './inbox/routes';
import { frontendURL } from '../../helper/URLHelper';
import helpcenterRoutes from './helpcenter/helpcenter.routes';
import campaignsRoutes from './campaigns/campaigns.routes';
import { routes as captainRoutes } from './captain/captain.routes';
import AppContainer from './Dashboard.vue';
import Suspended from './suspended/Index.vue';
import NoAccounts from './noAccounts/Index.vue';
import OnboardingAccountDetails from './onboarding/Index.vue';
import PatraAddChannel from './patra/PatraAddChannel.vue';
import PatraAiTraining from './patra/PatraAiTraining.vue';
import PatraOwnerDashboard from './patra/PatraOwnerDashboard.vue';
import PatraReports from './patra/PatraReports.vue';
import PatraFacebookAccounts from './patra/PatraFacebookAccounts.vue';
import PatraBackupPages from './patra/PatraBackupPages.vue';
import PatraTeamRoles from './patra/PatraTeamRoles.vue';
import PatraCashierQueue from './patra/PatraCashierQueue.vue';
import PatraReportsHub from './patra/PatraReportsHub.vue';
import PatraAuditLogs from './patra/PatraAuditLogs.vue';
import PatraFeedback from './patra/PatraFeedback.vue';
import broadcastsRoutes from './broadcasts/broadcasts.routes';
import Leaderboard from './reports/Leaderboard.vue';
import SweepsReport from './reports/SweepsReport.vue';
import KnowledgeBase from './settings/knowledge/KnowledgeBase.vue';
import CustomAttributesBuilder from './settings/attributes/CustomAttributesBuilder.vue';
import NotFound from './notFound/Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId'),
      component: AppContainer,
      children: [
        ...captainRoutes,
        ...inboxRoutes,
        ...conversation.routes,
        ...settings.routes,
        ...contactRoutes,
        ...companyRoutes,
        ...searchRoutes,
        ...notificationRoutes,
        ...helpcenterRoutes.routes,
        ...campaignsRoutes.routes,
        ...broadcastsRoutes.routes,
        {
          path: 'patra/dashboard',
          name: 'patra_owner_dashboard',
          component: PatraOwnerDashboard,
          meta: {
            permissions: ['administrator', 'agent'],
          },
        },
        {
          // Route name kept (`patra_connect_facebook`) so existing links in
          // MetaAppSettings, ChannelList, and onboarding/Index keep working
          // — the user-facing label and content are now generic "Add Channel"
          // for multi-platform Zernio OAuth (Phase H Issue 2 fix).
          path: 'patra/connect-facebook',
          name: 'patra_connect_facebook',
          component: PatraAddChannel,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          path: 'patra/facebook-accounts',
          name: 'patra_facebook_accounts',
          component: PatraFacebookAccounts,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          // Unified Connected Channels screen — same (repurposed) component,
          // reachable at the semantic /patra/channels URL.
          path: 'patra/channels',
          name: 'patra_channels',
          component: PatraFacebookAccounts,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          path: 'patra/backup-pages',
          name: 'patra_backup_pages',
          component: PatraBackupPages,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          path: 'patra/team-roles',
          name: 'patra_team_roles',
          component: PatraTeamRoles,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          path: 'patra/cashier-queue',
          name: 'patra_cashier_queue',
          component: PatraCashierQueue,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          path: 'patra/ai-training',
          name: 'patra_ai_training',
          component: PatraAiTraining,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          path: 'patra/reports',
          name: 'patra_reports',
          component: PatraReports,
          meta: {
            permissions: ['administrator', 'agent'],
          },
        },
        {
          // patra-final 2a: the Reports rail item lands here — a hub of all
          // report pages (sweepstakes + stock Chatwoot) with plain-English
          // descriptions. The sweepstakes report above stays the featured card.
          path: 'patra/reports-hub',
          name: 'patra_reports_hub',
          component: PatraReportsHub,
          meta: {
            permissions: ['administrator', 'agent'],
          },
        },
        {
          // patra-final 2c: Patra's own audit trail (AuditLog model +
          // patra_audit_logs API) finally gets a page. The EE audit-logs page
          // (auditlogs_list) is feature-gated off on the community plan.
          path: 'patra/audit-logs',
          name: 'patra_audit_logs',
          component: PatraAuditLogs,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          // patra-final P3: agent→owner feedback. Agents get a send form +
          // their own entries; admins get the inbox (filter, mark seen).
          path: 'patra/feedback',
          name: 'patra_feedback',
          component: PatraFeedback,
          meta: {
            permissions: ['administrator', 'agent'],
          },
        },
        {
          path: 'patra/leaderboard',
          name: 'patra_leaderboard',
          component: Leaderboard,
          meta: {
            permissions: ['administrator', 'agent'],
          },
        },
        // patra-fix2 F3: both audited spellings 404'd - the page lives at
        // patra/leaderboard (sidebar already points there); keep the other
        // two URLs working as aliases.
        {
          path: 'patra/agent-leaderboard',
          redirect: { name: 'patra_leaderboard' },
        },
        {
          path: 'reports/leaderboard',
          redirect: { name: 'patra_leaderboard' },
        },
        {
          path: 'patra/sweeps',
          name: 'patra_sweeps_report',
          component: SweepsReport,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          path: 'patra/knowledge',
          name: 'patra_knowledge',
          component: KnowledgeBase,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          path: 'patra/custom-attributes',
          name: 'patra_custom_attributes',
          component: CustomAttributesBuilder,
          meta: {
            permissions: ['administrator'],
          },
        },
        // Named catch-all: unmatched account URLs resolve to a real 404 page.
        // A named route keeps the router guard's `!to.name` redirect from
        // dumping users into the inbox. MUST stay last so it only matches when
        // nothing else does.
        {
          path: ':pathMatch(.*)*',
          name: 'not_found',
          component: NotFound,
          meta: { permissions: ['administrator', 'agent'] },
        },
      ],
    },
    {
      path: frontendURL('accounts/:accountId/onboarding'),
      name: 'onboarding_account_details',
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
      component: OnboardingAccountDetails,
    },
    {
      path: frontendURL('accounts/:accountId/suspended'),
      name: 'account_suspended',
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
      component: Suspended,
    },
    {
      path: frontendURL('no-accounts'),
      name: 'no_accounts',
      component: NoAccounts,
    },
  ],
};
