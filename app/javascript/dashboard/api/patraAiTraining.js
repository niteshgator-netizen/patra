/* global axios */
import ApiClient from './ApiClient';

// Phase H.10 item 10: API client for the Patra AI Training page
// (uploads, takeover review queue, secret phrases).
class PatraAiTrainingAPI extends ApiClient {
  constructor() {
    super('', { accountScoped: true });
  }

  // ── Bella RAG uploads ──────────────────────────────────────────────

  listUploads() {
    return axios.get(`${this.url}/bella_rag_uploads`);
  }

  uploadTrainingFile(file) {
    const formData = new FormData();
    formData.append('file', file);
    return axios.post(`${this.url}/bella_rag_uploads`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  // ── Takeover review queue ──────────────────────────────────────────

  listCandidates(status = 'queued') {
    return axios.get(`${this.url}/bella_takeover_candidates`, {
      params: { status },
    });
  }

  updateCandidate(id, status) {
    return axios.patch(`${this.url}/bella_takeover_candidates/${id}`, {
      bella_takeover_candidate: { status },
    });
  }

  // ── Secret phrases ─────────────────────────────────────────────────

  listSecretPhrases() {
    return axios.get(`${this.url}/secret_phrases`);
  }

  createSecretPhrase(payload) {
    return axios.post(`${this.url}/secret_phrases`, {
      secret_phrase: payload,
    });
  }

  updateSecretPhrase(id, payload) {
    return axios.patch(`${this.url}/secret_phrases/${id}`, {
      secret_phrase: payload,
    });
  }

  deleteSecretPhrase(id) {
    return axios.delete(`${this.url}/secret_phrases/${id}`);
  }
}

export default new PatraAiTrainingAPI();
