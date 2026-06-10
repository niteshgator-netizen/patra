# frozen_string_literal: true

# Focused specs for the non-hot AI service fleet. All LLM calls mocked.
require 'rails_helper'

RSpec.describe 'AI service fleet' do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  describe Ai::CopilotService do
    it 'routes through the shared DeepSeek client and strips the result' do
      allow(Ai::DeepseekClient).to receive(:complete).and_return("  sure thing  \n")

      expect(described_class.call_ai('prompt')).to eq('sure thing')
    end

    it 'returns an empty string (never raises) when the model fails' do
      allow(Ai::DeepseekClient).to receive(:complete).and_return(nil)
      expect(described_class.call_ai('prompt')).to eq('')

      allow(Ai::DeepseekClient).to receive(:complete).and_raise(StandardError, 'down')
      expect(described_class.call_ai('prompt')).to eq('')
    end
  end

  describe Ai::TagSuggester do
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    it 'parses comma-separated hashtags into clean tag names, max 3' do
      allow(Ai::CopilotService).to receive(:call_ai).and_return('#loads, #cashout , #vip, #extra')

      expect(described_class.suggest(conversation)).to eq(%w[loads cashout vip])
    end

    it 'returns [] when the model gives nothing' do
      allow(Ai::CopilotService).to receive(:call_ai).and_return('')

      expect(described_class.suggest(conversation)).to eq([])
    end
  end

  describe Ai::EnhancedBusinessHoursChecker do
    it 'is closed on an account-wide holiday' do
      create(:holiday, account: account, closed_on: Date.current)

      expect(described_class.open_now?(account)).to be false
    end

    it 'fails OPEN when the holiday lookup blows up' do
      allow(Holiday).to receive(:for_account).and_raise(StandardError, 'db down')

      expect(described_class.open_now?(account)).to be true
    end

    it 'is open when no hours are configured' do
      expect(described_class.open_now?(account)).to be true
    end
  end

  describe Ai::SentimentScorer do
    it 'scores keyword sentiment with negative taking precedence' do
      expect(described_class.score('thanks, that was great')).to eq('positive')
      expect(described_class.score('this is a scam, thanks for nothing')).to eq('negative')
      expect(described_class.score('loading juwa now')).to eq('neutral')
      expect(described_class.score(nil)).to eq('neutral')
    end
  end

  describe Ai::ComplexityClassifier do
    it 'routes money/game/escalation talk as complex' do
      expect(described_class.classify('can you load $20 on juwa')).to eq(:complex)
      expect(described_class.classify('i want a refund')).to eq(:complex)
      expect(described_class.classify('kara123 is my username')).to eq(:complex)
    end

    it 'routes greetings and acks as simple' do
      expect(described_class.classify('hey')).to eq(:simple)
      expect(described_class.classify('thanks!')).to eq(:simple)
    end

    it 'flags attachments and defaults unknown prose to complex' do
      expect(described_class.classify('whatever', has_attachment: true)).to eq(:has_image)
      expect(described_class.classify('the weather is something else today friend')).to eq(:complex)
    end
  end

  describe Ai::VaultContextBuilder do
    it 'lists per-slug credentials using game_username_<slug>/game_password_<slug>' do
      create(:game, slug: 'juwa', name: 'Juwa')
      contact.update!(custom_attributes: {
                        'game_username_juwa' => 'kara123',
                        'game_password_juwa' => 'pw1',
                        'game_username_vblink' => 'kara_vb'
                      })

      out = described_class.for_contact(contact.reload)

      expect(out).to include('Game: Juwa, Username: kara123, Password: pw1')
      expect(out).to include('Username: kara_vb')
    end

    it 'dedupes slug casing preferring the entry with a password' do
      contact.update!(custom_attributes: {
                        'game_username_Juwa' => 'old_name',
                        'game_username_juwa' => 'kara123',
                        'game_password_juwa' => 'pw1'
                      })

      out = described_class.for_contact(contact.reload)

      expect(out.scan(/Game: /).length).to eq(1)
      expect(out).to include('kara123')
    end

    it 'returns an empty string for a contact with nothing on file' do
      expect(described_class.for_contact(contact)).to eq('')
    end
  end

  describe Ai::PlayerMemoryWriter do
    let(:writer) { described_class.new(contact: contact) }

    it 'keeps the old memory intact when the model fails' do
      contact.update!(custom_attributes: {
                        'patra_player_memory' => { 'summary' => 'chatty regular', 'messages_summarized' => 500 }
                      })
      allow(Ai::DeepseekClient).to receive(:complete).and_return(nil)

      memory = writer.fold([{ 'message_type' => 'incoming', 'content' => 'yo' }], persist: false)

      expect(memory['summary']).to eq('chatty regular')
      expect(memory['messages_summarized']).to eq(500)
    end

    it 'caps the stored summary at SUMMARY_CHARS_CAP' do
      long = 'x' * 10_000
      memory = writer.build_memory(writer.current_memory, %({"summary":"#{long}","traits":{}}), 500)

      expect(memory['summary'].length).to eq(described_class::SUMMARY_CHARS_CAP)
    end

    it 'advances messages_summarized by the folded count' do
      memory = writer.build_memory(
        { 'summary' => '', 'traits' => {}, 'messages_summarized' => 500 },
        '{"summary":"s","traits":{}}',
        500
      )

      expect(memory['messages_summarized']).to eq(1000)
    end

    it 'treats non-JSON model output as the summary prose' do
      memory = writer.build_memory(writer.current_memory, 'just a plain sentence', 10)

      expect(memory['summary']).to eq('just a plain sentence')
    end
  end

  describe RotatePlayerMemoryJob do
    it 'folds the oldest 500 only once 1000 unsummarized messages accumulate' do
      expect(described_class.fold_plan(total_messages: 999, messages_summarized: 0)).to be_nil
      expect(described_class.fold_plan(total_messages: 1000, messages_summarized: 0))
        .to eq(batch_size: 500, new_summarized: 500)
      # after a fold, remaining 500 unsummarized is below trigger — idempotent on rerun
      expect(described_class.fold_plan(total_messages: 1000, messages_summarized: 500)).to be_nil
      expect(described_class.fold_plan(total_messages: 1500, messages_summarized: 500))
        .to eq(batch_size: 500, new_summarized: 1000)
    end
  end

  describe Ai::ImagePaymentExtractor do
    it 'returns a safe non-payment hash for a blank url' do
      expect(described_class.new('').extract).to include(is_payment: false)
    end

    it 'returns a safe hash when the api key is missing' do
      with_modified_env GEMINI_API_KEY: nil do
        expect(described_class.new('https://img.test/x.png').extract).to include(is_payment: false)
      end
    end

    it 'returns download_failed (never raises) on a bad image url' do
      with_modified_env GEMINI_API_KEY: 'k' do
        stub_request(:get, 'https://img.test/x.png').to_return(status: 404)

        result = described_class.new('https://img.test/x.png').extract

        expect(result[:is_payment]).to be false
        expect(result[:error]).to eq('download_failed')
      end
    end

    it 'extracts amount/platform/sender from a clean vision response' do
      with_modified_env GEMINI_API_KEY: 'k' do
        stub_request(:get, 'https://img.test/x.png')
          .to_return(status: 200, body: 'imgbytes', headers: { 'Content-Type' => 'image/png' })
        vision = {
          'candidates' => [{ 'content' => { 'parts' => [{
            'text' => '```json {"is_payment":true,"platform":"cashapp","amount":25.0,"sender_name":"Kara M","confidence":0.95} ```'
          }] } }]
        }
        stub_request(:post, %r{generativelanguage\.googleapis\.com}).to_return(
          status: 200, body: vision.to_json, headers: { 'Content-Type' => 'application/json' }
        )

        result = described_class.new('https://img.test/x.png').extract

        expect(result[:is_payment]).to be true
        expect(result[:amount]).to eq(25.0)
        expect(result[:platform]).to eq('cashapp')
        expect(result[:sender_name]).to eq('Kara M')
      end
    end

    it 'returns a parse_error hash on garbage model output' do
      with_modified_env GEMINI_API_KEY: 'k' do
        stub_request(:get, 'https://img.test/x.png')
          .to_return(status: 200, body: 'imgbytes', headers: { 'Content-Type' => 'image/png' })
        stub_request(:post, %r{generativelanguage\.googleapis\.com}).to_return(
          status: 200,
          body: { 'candidates' => [{ 'content' => { 'parts' => [{ 'text' => 'not json at all' }] } }] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

        result = described_class.new('https://img.test/x.png').extract

        expect(result[:is_payment]).to be false
      end
    end
  end
end
