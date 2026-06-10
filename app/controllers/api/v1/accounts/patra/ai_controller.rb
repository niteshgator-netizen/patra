# frozen_string_literal: true

class Api::V1::Accounts::Patra::AiController < Api::V1::Accounts::BaseController
  before_action :set_conversation, only: [:copilot_suggestion, :summarize, :suggest_tags, :smart_compose]

  def copilot_suggestion
    suggestion = Ai::CopilotService.suggest(conversation: @conversation, draft: params[:draft])
    render json: { suggestion: suggestion }
  end

  def summarize
    summary = Ai::SummaryService.summarize(@conversation)
    attrs = @conversation.custom_attributes || {}
    attrs['ai_summary'] = summary
    @conversation.update!(custom_attributes: attrs)
    render json: { summary: summary }
  end

  def suggest_tags
    tags = Ai::TagSuggester.suggest(@conversation)
    render json: { tags: tags }
  end

  def smart_compose
    completion = Ai::SmartCompose.complete(conversation: @conversation, prefix: params[:prefix])
    render json: { completion: completion }
  end

  def translate
    text = params[:text]
    target = params[:target_language] || 'en'
    translated = Ai::TranslationService.translate(text: text, target: target)
    render json: { translated: translated }
  end

  def analyze_image
    attachment = ActiveStorage::Blob.find_signed(params[:blob_signed_id])
    analysis = Ai::ImageAnalyzer.analyze(attachment)
    render json: { analysis: analysis }
  end

  private

  def set_conversation
    @conversation = Current.account.conversations.find(params[:conversation_id])
    authorize @conversation, :show?
  end
end
