import { FEATURE_FLAGS } from '../../../../featureFlags';
import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import Automation from './Index.vue';
import FlowList from './FlowList.vue';
import FlowBuilder from './FlowBuilder.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/automation'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'automation_list', params: to.params };
          },
        },
        {
          path: 'list',
          name: 'automation_list',
          component: Automation,
          meta: {
            featureFlag: FEATURE_FLAGS.AUTOMATIONS,
            permissions: ['administrator'],
          },
        },
        {
          path: 'flows',
          name: 'patra_flow_list',
          component: FlowList,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          path: 'flows/new',
          name: 'patra_flow_builder_new',
          component: FlowBuilder,
          meta: {
            permissions: ['administrator'],
          },
        },
        {
          path: 'flows/:flowId',
          name: 'patra_flow_builder',
          component: FlowBuilder,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
