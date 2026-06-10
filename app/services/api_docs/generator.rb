# frozen_string_literal: true

module ApiDocs
  class Generator
    ENDPOINTS = [
      { method: 'GET', path: '/api/v1/accounts/:account_id/automation_flows', description: 'List automation flows' },
      { method: 'POST', path: '/api/v1/accounts/:account_id/automation_flows', description: 'Create automation flow' },
      { method: 'GET', path: '/api/v1/accounts/:account_id/broadcasts', description: 'List broadcasts' },
      { method: 'POST', path: '/api/v1/accounts/:account_id/broadcasts', description: 'Create broadcast' },
      { method: 'GET', path: '/api/v1/accounts/:account_id/knowledge_articles', description: 'List knowledge articles' },
      { method: 'GET', path: '/api/v1/accounts/:account_id/patra/dashboard', description: 'Owner dashboard stats' },
      { method: 'GET', path: '/api/v1/accounts/:account_id/patra/reports', description: 'Sweepstakes reports' },
      { method: 'GET', path: '/api/v1/accounts/:account_id/cashier_claims', description: 'Cashier queue' },
      { method: 'POST', path: '/api/v1/accounts/:account_id/patra/ai/copilot_suggestion', description: 'AI copilot suggestion' },
      { method: 'POST', path: '/api/v1/accounts/:account_id/conversations/:conversation_id/patra_ai_analysis',
        description: 'AI analysis of a conversation (intent, sentiment, entities, safety, suggested reply); persists to conversation custom_attributes' },
      { method: 'POST', path: '/api/v1/accounts/:account_id/patra_playground/messages',
        description: 'Persona playground: body {message, context?} -> {reply, prompt}; no persistence, no sends' }
    ].freeze

    def self.generate
      { version: 'v1', endpoints: ENDPOINTS }
    end
  end
end
