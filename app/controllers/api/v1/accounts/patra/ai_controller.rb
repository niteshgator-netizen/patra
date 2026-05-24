# frozen_string_literal: true

class Api::V1::Accounts::Patra::AiController < Api::V1::Accounts::BaseController
  def copilot_suggestion
    conversation = Current.account.conversations.find(params[:conversation_id])
    suggestion = Ai::CopilotService.suggest(conversation: conversation, draft: params[:draft])
    render json: { suggestion: suggestion }
  end

  def summarize
    conversation = Current.account.conversations.find(params[:conversation_id])
    summary = Ai::SummaryService.summarize(conversation)
    attrs = conversation.custom_attributes || {}
    attrs['ai_summary'] = summary
    conversation.update!(custom_attributes: attrs)
    render json: { summary: summary }
  end

  def suggest_tags
    conversation = Current.account.conversations.find(params[:conversation_id])
    tags = Ai::TagSuggester.suggest(conversation)
    render json: { tags: tags }
  end

  def smart_compose
    conversation = Current.account.conversations.find(params[:conversation_id])
    completion = Ai::SmartCompose.complete(conversation: conversation, prefix: params[:prefix])
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
end
