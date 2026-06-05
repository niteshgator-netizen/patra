/* global axios */

const getReferrals = (accountId, page = 1) =>
  axios.get(`/api/v1/accounts/${accountId}/referrals`, { params: { page } });

const createReferral = (accountId, data) =>
  axios.post(`/api/v1/accounts/${accountId}/referrals`, {
    referral: data,
  });

const updateReferral = (accountId, referralId, data) =>
  axios.put(`/api/v1/accounts/${accountId}/referrals/${referralId}`, {
    referral: data,
  });

export default { getReferrals, createReferral, updateReferral };
