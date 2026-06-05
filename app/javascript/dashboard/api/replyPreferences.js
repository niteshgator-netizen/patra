/* global axios */

const getReplyPreference = accountId =>
  axios.get(`/api/v1/accounts/${accountId}/reply_preference`);

const updateReplyPreference = (accountId, data) =>
  axios.put(`/api/v1/accounts/${accountId}/reply_preference`, {
    reply_preference: data,
  });

export default { getReplyPreference, updateReplyPreference };
