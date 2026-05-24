import { frontendURL } from '../../../helper/URLHelper';
import BroadcastList from './BroadcastList.vue';
import BroadcastComposer from './BroadcastComposer.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/broadcasts'),
      name: 'patra_broadcast_list',
      component: BroadcastList,
      meta: { permissions: ['administrator'] },
    },
    {
      path: frontendURL('accounts/:accountId/broadcasts/new'),
      name: 'patra_broadcast_compose_new',
      component: BroadcastComposer,
      meta: { permissions: ['administrator'] },
    },
    {
      path: frontendURL('accounts/:accountId/broadcasts/:broadcastId'),
      name: 'patra_broadcast_compose',
      component: BroadcastComposer,
      meta: { permissions: ['administrator'] },
    },
  ],
};
