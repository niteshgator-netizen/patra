/* global axios */
import ApiClient from './ApiClient';

class PatraReportsAPI extends ApiClient {
  constructor() {
    super('patra/reports', { accountScoped: true });
  }

  // agentPeriod: 'today' | 'week' | 'month' — scopes the agent_performance
  // block only; everything else keeps its fixed windows.
  get(agentPeriod) {
    return axios.get(this.url, {
      params: agentPeriod ? { agent_period: agentPeriod } : {},
    });
  }

  // period: 'day' | 'week'
  sweeps(period) {
    return axios.get(`${this.url}/sweeps`, { params: { period } });
  }

  sweepsCsvUrl(period) {
    return `${this.url}/sweeps.csv?period=${period}`;
  }
}

export default new PatraReportsAPI();
