require 'rails_helper'

RSpec.describe 'Webhooks::TelegramController secret validation', type: :request do
  let(:bot_token) { 'random_bot_token' }
  let(:valid_secret) { Webhooks::TelegramSecret.for(bot_token) }

  describe Webhooks::TelegramSecret do
    it 'derives a deterministic url-safe secret from the bot token' do
      expect(valid_secret).to eq(Webhooks::TelegramSecret.for(bot_token))
      expect(valid_secret).to match(/\A[A-Za-z0-9_-]{1,256}\z/)
    end

    it 'derives different secrets for different bot tokens' do
      expect(valid_secret).not_to eq(Webhooks::TelegramSecret.for('other_token'))
    end
  end

  describe 'POST /webhooks/telegram/{:bot_token}' do
    context 'when enforcement is off (default)' do
      it 'accepts payloads without the secret header but logs a warning' do
        allow(Webhooks::TelegramEventsJob).to receive(:perform_later)
        allow(Rails.logger).to receive(:warn)

        post "/webhooks/telegram/#{bot_token}", params: { content: 'hello' }

        expect(response).to have_http_status(:success)
        expect(Webhooks::TelegramEventsJob).to have_received(:perform_later)
        expect(Rails.logger).to have_received(:warn).with(/secret token/)
      end

      it 'accepts payloads with a valid secret header without warning' do
        allow(Webhooks::TelegramEventsJob).to receive(:perform_later)
        allow(Rails.logger).to receive(:warn)

        post "/webhooks/telegram/#{bot_token}", params: { content: 'hello' },
                                                headers: { 'X-Telegram-Bot-Api-Secret-Token' => valid_secret }

        expect(response).to have_http_status(:success)
        expect(Webhooks::TelegramEventsJob).to have_received(:perform_later)
        expect(Rails.logger).not_to have_received(:warn).with(/secret token/)
      end
    end

    context 'when enforcement is on' do
      it 'rejects payloads with a missing secret header and does not enqueue the job' do
        with_modified_env TELEGRAM_WEBHOOK_VALIDATE_SECRET: 'true' do
          allow(Webhooks::TelegramEventsJob).to receive(:perform_later)

          post "/webhooks/telegram/#{bot_token}", params: { content: 'forged' }

          expect(response).to have_http_status(:unauthorized)
          expect(Webhooks::TelegramEventsJob).not_to have_received(:perform_later)
        end
      end

      it 'rejects payloads with a wrong secret header' do
        with_modified_env TELEGRAM_WEBHOOK_VALIDATE_SECRET: 'true' do
          allow(Webhooks::TelegramEventsJob).to receive(:perform_later)

          post "/webhooks/telegram/#{bot_token}", params: { content: 'forged' },
                                                  headers: { 'X-Telegram-Bot-Api-Secret-Token' => 'wrong' }

          expect(response).to have_http_status(:unauthorized)
          expect(Webhooks::TelegramEventsJob).not_to have_received(:perform_later)
        end
      end

      it 'accepts payloads carrying the derived secret' do
        with_modified_env TELEGRAM_WEBHOOK_VALIDATE_SECRET: 'true' do
          allow(Webhooks::TelegramEventsJob).to receive(:perform_later)

          post "/webhooks/telegram/#{bot_token}", params: { content: 'hello' },
                                                  headers: { 'X-Telegram-Bot-Api-Secret-Token' => valid_secret }

          expect(response).to have_http_status(:success)
          expect(Webhooks::TelegramEventsJob).to have_received(:perform_later)
        end
      end
    end
  end
end
