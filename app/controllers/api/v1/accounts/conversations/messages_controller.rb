class Api::V1::Accounts::Conversations::MessagesController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_api_inbox, only: :update, unless: :pin_update_requested?

  def index
    @messages = message_finder.perform
  end

  def create
    user = Current.user || @resource
    mb = Messages::MessageBuilder.new(user, @conversation, params)
    @message = mb.perform
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def update
    if pin_update_requested?
      update_message_pin
    else
      Messages::StatusUpdateService.new(message, permitted_params[:status], permitted_params[:external_error]).perform
    end
    @message = message.reload
  end

  def destroy
    ActiveRecord::Base.transaction do
      message.update!(content: I18n.t('conversations.messages.deleted'), content_type: :text, content_attributes: { deleted: true })
      message.attachments.destroy_all
    end
  end

  def retry
    return if message.blank?

    service = Messages::StatusUpdateService.new(message, 'sent')
    service.perform
    message.update!(content_attributes: {})
    ::SendReplyJob.perform_later(message.id)
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def translate
    return head :ok if already_translated_content_available?

    translated_content = Integrations::GoogleTranslate::ProcessorService.new(
      message: message,
      target_language: permitted_params[:target_language]
    ).perform

    if translated_content.present?
      translations = {}
      translations[permitted_params[:target_language]] = translated_content
      translations = message.translations.merge!(translations) if message.translations.present?
      message.update!(translations: translations)
    end

    render json: { content: translated_content }
  end

  private

  def message
    @message ||= @conversation.messages.find(permitted_params[:id])
  end

  def message_finder
    @message_finder ||= MessageFinder.new(@conversation, params)
  end

  def permitted_params
    params.permit(:id, :target_language, :status, :external_error, content_attributes: [:pinned])
  end

  def pin_update_requested?
    content_attributes_params.key?(:pinned)
  end

  def content_attributes_params
    permitted_params.fetch(:content_attributes, ActionController::Parameters.new).permit(:pinned)
  end

  def update_message_pin
    attrs = message.content_attributes.to_h.stringify_keys
    pinned = ActiveModel::Type::Boolean.new.cast(content_attributes_params[:pinned])

    if pinned
      attrs['pinned'] = true
      attrs['pinned_at'] = Time.current.to_i
    else
      attrs.delete('pinned')
      attrs.delete('pinned_at')
    end

    message.update!(content_attributes: attrs)
  end

  def already_translated_content_available?
    message.translations.present? && message.translations[permitted_params[:target_language]].present?
  end

  # API inbox check
  def ensure_api_inbox
    # Only API inboxes can update messages
    render json: { error: 'Message status update is only allowed for API inboxes' }, status: :forbidden unless @conversation.inbox.api?
  end
end
