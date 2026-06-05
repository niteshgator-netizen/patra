/* global axios */

const getGameRules = accountId =>
  axios.get(`/api/v1/accounts/${accountId}/game_rules`);

const getGameRule = (accountId, gameId) =>
  axios.get(`/api/v1/accounts/${accountId}/game_rules/${gameId}`);

const updateGameRule = (accountId, gameId, data) =>
  axios.put(`/api/v1/accounts/${accountId}/game_rules/${gameId}`, {
    game_rule: data,
  });

export default { getGameRules, getGameRule, updateGameRule };
