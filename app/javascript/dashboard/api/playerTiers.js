/* global axios */

const getPlayerTiers = accountId =>
  axios.get(`/api/v1/accounts/${accountId}/player_tiers`);

const createPlayerTier = (accountId, data) =>
  axios.post(`/api/v1/accounts/${accountId}/player_tiers`, {
    player_tier: data,
  });

const updatePlayerTier = (accountId, tierId, data) =>
  axios.put(`/api/v1/accounts/${accountId}/player_tiers/${tierId}`, {
    player_tier: data,
  });

const deletePlayerTier = (accountId, tierId) =>
  axios.delete(`/api/v1/accounts/${accountId}/player_tiers/${tierId}`);

const bulkAssignTier = (accountId, contactIds, tierId) =>
  axios.post(`/api/v1/accounts/${accountId}/contacts/bulk_tier`, {
    contact_ids: contactIds,
    player_tier_id: tierId,
  });

export default {
  getPlayerTiers,
  createPlayerTier,
  updatePlayerTier,
  deletePlayerTier,
  bulkAssignTier,
};
