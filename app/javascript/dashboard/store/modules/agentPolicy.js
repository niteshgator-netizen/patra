// it6 (policy-ui B2) — Agent Policy store module. The policy lives at account.settings['agent_policy']
// (validated server-side by AGENT_POLICY_SCHEMA), so READ is via the account (useAccount().currentAccount)
// and WRITE composes the REAL, validated account-update path (accounts/update) — no fake REST endpoint.
const state = {
  uiFlags: {
    isUpdating: false,
  },
};

const getters = {
  getAgentPolicyUIFlags: _state => _state.uiFlags,
};

const actions = {
  // Persist the full agent_policy object via the account-settings update (admin-only, schema-validated).
  updateAgentPolicy: async ({ commit, dispatch }, policy) => {
    commit('SET_UI_FLAG', { isUpdating: true });
    try {
      await dispatch('accounts/update', { agent_policy: policy }, { root: true });
      commit('SET_UI_FLAG', { isUpdating: false });
    } catch (error) {
      commit('SET_UI_FLAG', { isUpdating: false });
      throw error;
    }
  },
};

const mutations = {
  SET_UI_FLAG(_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
