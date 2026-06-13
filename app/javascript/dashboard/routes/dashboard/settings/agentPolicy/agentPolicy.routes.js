import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import AgentPolicyHome from './Index.vue';

// it6 (policy-ui B4) — admin/owner-gated Agent Policy settings page. Same gating pattern as the
// Games integration page (meta.permissions: ['administrator']).
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/agent-policy'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'settings_agent_policy_index',
          component: AgentPolicyHome,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
