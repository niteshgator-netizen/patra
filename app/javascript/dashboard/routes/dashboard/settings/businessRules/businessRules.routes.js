import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import GameRulesIndex from '../gameRules/Index.vue';
import PlayerTiersIndex from '../playerTiers/Index.vue';
import ReferralsIndex from '../referrals/Index.vue';
import ReplyStyleIndex from '../replyStyle/Index.vue';

const meta = {
  permissions: ['administrator'],
};

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/game-rules'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'settings_game_rules',
          component: GameRulesIndex,
          meta,
        },
      ],
    },
    {
      path: frontendURL('accounts/:accountId/settings/player-tiers'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'settings_player_tiers',
          component: PlayerTiersIndex,
          meta,
        },
      ],
    },
    {
      path: frontendURL('accounts/:accountId/settings/referrals'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'settings_referrals',
          component: ReferralsIndex,
          meta,
        },
      ],
    },
    {
      path: frontendURL('accounts/:accountId/settings/reply-style'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'settings_reply_style',
          component: ReplyStyleIndex,
          meta,
        },
      ],
    },
  ],
};
