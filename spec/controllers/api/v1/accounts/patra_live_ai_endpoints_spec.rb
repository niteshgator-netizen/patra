# frozen_string_literal: true

# HB-1 (conversation AI analysis) + HB-2 (persona playground). DeepSeek mocked.
require 'rails_helper'

RSpec.describe 'Patra live-AI endpoints', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
  end

  describe 'POST /api/v1/accounts/:id/conversations/:conversation_id/patra_ai_analysis' do
    let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/patra_ai_analysis" }
    let(:clean_json) do
      '{"intent":"load_request","sentiment":"positive","entities":["juwa","$20"],' \
        '"safety_check":{"status":"ok","note":""},"suggested_reply":"on it! loading your juwa now",' \
        '"confidence":92}'
    end

    before do
      create(:message, account: account, inbox: inbox, conversation: conversation,
                       message_type: :incoming, content: 'load 20 on juwa')
    end

    it 'requires authentication' do
      post url, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'analyzes, persists once to custom_attributes, and returns the analysis' do
      allow(Ai::DeepseekClient).to receive(:complete).and_return(clean_json)

      post url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body['analysis']
      expect(body['intent']).to eq('load_request')
      expect(body['confidence']).to eq(92)
      expect(body['safety_check']['status']).to eq('ok')

      stored = conversation.reload.custom_attributes['patra_ai_analysis']
      expect(stored['intent']).to eq('load_request')
      expect(stored['analyzed_at']).to be_present
    end

    it 'strips markdown fences from the model output' do
      allow(Ai::DeepseekClient).to receive(:complete).and_return("```json\n#{clean_json}\n```")

      post url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.dig('analysis', 'intent')).to eq('load_request')
    end

    it 'returns 422 on unparseable model output without persisting' do
      allow(Ai::DeepseekClient).to receive(:complete).and_return('sorry, no json here')

      post url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(conversation.reload.custom_attributes.to_h['patra_ai_analysis']).to be_nil
    end

    it 'returns 503 when the model is unavailable' do
      allow(Ai::DeepseekClient).to receive(:complete).and_return(nil)

      post url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:service_unavailable)
    end

    it 'clamps confidence into 0-100' do
      allow(Ai::DeepseekClient).to receive(:complete).and_return(
        clean_json.sub('"confidence":92', '"confidence":900')
      )

      post url, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body.dig('analysis', 'confidence')).to eq(100)
    end

    it 'cannot analyze another account\'s conversation' do
      other = create(:account)
      other_inbox = create(:inbox, account: other)
      other_conv = create(:conversation, account: other, inbox: other_inbox,
                          contact: create(:contact, account: other))

      post "/api/v1/accounts/#{account.id}/conversations/#{other_conv.display_id}/patra_ai_analysis",
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/accounts/:id/patra_playground/messages' do
    let(:url) { "/api/v1/accounts/#{account.id}/patra_playground/messages" }

    it 'requires authentication' do
      post url, params: { message: 'yo' }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the persona reply and the prompt used, persisting nothing' do
      allow(Ai::DeepseekClient).to receive(:complete).and_return("yo! what game you on?\ni got you")

      expect do
        post url, params: { message: 'can i get a load', context: 'vip player' },
                  headers: agent.create_new_auth_token, as: :json
      end.not_to change(Message, :count)

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['reply']).to eq("yo! what game you on?\ni got you")
      expect(body['prompt']).to include('Maximum 2 short lines')
      expect(body['prompt']).to include('vip player')
    end

    it 'hard-caps the reply at 2 lines even if the model rambles' do
      allow(Ai::DeepseekClient).to receive(:complete).and_return("one\ntwo\nthree\nfour")

      post url, params: { message: 'hi' }, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['reply']).to eq("one\ntwo")
    end

    it 'rejects a blank message' do
      post url, params: { message: '  ' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 503 when the model is down' do
      allow(Ai::DeepseekClient).to receive(:complete).and_return(nil)

      post url, params: { message: 'hi' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:service_unavailable)
    end
  end
end
