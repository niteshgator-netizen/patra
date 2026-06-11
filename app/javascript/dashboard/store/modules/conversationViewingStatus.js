import * as types from '../mutation-types';
import ConversationAPI from '../../api/inbox/conversation';

// 4b collision detection — who has a conversation open right now.
// Mirrors conversationTypingStatus, plus a stale-entry timer: viewers
// re-announce every ANNOUNCE_INTERVAL_MS from the conversation header, so an
// entry that isn't refreshed within STALE_AFTER_MS (crashed tab, lost socket)
// is dropped instead of showing a ghost "is viewing" badge forever.
export const ANNOUNCE_INTERVAL_MS = 60000;
const STALE_AFTER_MS = 150000;

// conversationId -> userKey -> timeout handle (module-local, not reactive)
const staleTimers = {};

const userKey = user => `${user.type || 'user'}-${user.id}`;

const clearStaleTimer = (conversationId, user) => {
  const key = `${conversationId}:${userKey(user)}`;
  if (staleTimers[key]) {
    clearTimeout(staleTimers[key]);
    delete staleTimers[key];
  }
};

const state = {
  records: {},
};

export const getters = {
  getUserList: $state => id => {
    return $state.records[Number(id)] || [];
  },
};

export const actions = {
  toggleViewing: async (_, { status, conversationId }) => {
    try {
      await ConversationAPI.toggleViewing({ status, conversationId });
    } catch (error) {
      // Viewing is best-effort presence — never surface an error for it.
    }
  },
  create: ({ commit, dispatch }, { conversationId, user }) => {
    commit(types.default.ADD_USER_VIEWING_TO_CONVERSATION, {
      conversationId,
      user,
    });
    clearStaleTimer(conversationId, user);
    staleTimers[`${conversationId}:${userKey(user)}`] = setTimeout(() => {
      dispatch('destroy', { conversationId, user });
    }, STALE_AFTER_MS);
  },
  destroy: ({ commit }, { conversationId, user }) => {
    clearStaleTimer(conversationId, user);
    commit(types.default.REMOVE_USER_VIEWING_FROM_CONVERSATION, {
      conversationId,
      user,
    });
  },
};

export const mutations = {
  [types.default.ADD_USER_VIEWING_TO_CONVERSATION]: (
    $state,
    { conversationId, user }
  ) => {
    const records = $state.records[conversationId] || [];
    const hasUserRecordAlready = !!records.filter(
      record => record.id === user.id && record.type === user.type
    ).length;
    if (!hasUserRecordAlready) {
      $state.records = {
        ...$state.records,
        [conversationId]: [...records, user],
      };
    }
  },
  [types.default.REMOVE_USER_VIEWING_FROM_CONVERSATION]: (
    $state,
    { conversationId, user }
  ) => {
    const records = $state.records[conversationId] || [];
    const updatedRecords = records.filter(
      record => record.id !== user.id || record.type !== user.type
    );
    $state.records = {
      ...$state.records,
      [conversationId]: updatedRecords,
    };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
