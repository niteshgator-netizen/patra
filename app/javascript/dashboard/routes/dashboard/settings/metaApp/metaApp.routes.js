import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import MetaAppSettings from './MetaAppSettings.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/meta-app'),
      meta: {
        permissions: ['administrator'],
      },
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'settings_meta_app',
          component: MetaAppSettings,
          meta: {
            permissions: ['administrator'],
          },
        },
      ],
    },
  ],
};
