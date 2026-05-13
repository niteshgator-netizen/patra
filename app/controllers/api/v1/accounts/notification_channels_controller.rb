class Api::V1::Accounts::NotificationChannelsController < Api::V1::Accounts::BaseController
  before_action :fetch_channel, only: [:show, :update, :destroy, :test_connection]

  def index
    channels = Current.account.notification_channels.order(:channel_type)
    render json: { data: channels.map { |c| serialize(c) } }
  end

  def show
    render json: { data: serialize(@channel) }
  end

  def create
    channel = Current.account.notification_channels.new(create_params)
    channel.event_filters = NotificationChannel::DEFAULT_EVENT_FILTERS if channel.event_filters.blank?
    channel.status = params[:status].presence || 'active'
    if channel.save
      render json: { data: serialize(channel) }, status: :created
    else
      render json: { error: channel.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def update
    merged = (@channel.credentials || {}).merge(extract_credentials(params))
    @channel.assign_attributes(
      credentials: merged,
      status: params[:status].presence || @channel.status,
      event_filters: params[:event_filters].presence || @channel.event_filters
    )
    if @channel.save
      render json: { data: serialize(@channel) }
    else
      render json: { error: @channel.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def destroy
    @channel.destroy
    head :no_content
  end

  def test_connection
    creds = @channel.credentials || {}
    bot_token = creds['bot_token']
    chat_id = creds['chat_id']
    if bot_token.blank? || chat_id.blank?
      @channel.record_test!(success: false, message: 'Missing bot token or chat ID')
      return render json: { ok: false, error: 'Missing bot token or chat ID' }, status: :unprocessable_entity
    end

    text = "🎯 *Patra connection test*\n\nIf you see this, your Telegram notifications are wired up correctly\\."
    result = Games::TelegramNotifier.send_raw(bot_token: bot_token, chat_id: chat_id, text: text)

    if result[:ok]
      @channel.record_test!(success: true, message: 'Test message delivered')
      render json: { ok: true, message: 'Test message delivered' }
    else
      err = result[:body] || result[:error] || "HTTP #{result[:status]}"
      @channel.record_test!(success: false, message: err)
      render json: { ok: false, error: err }, status: :unprocessable_entity
    end
  end

  private

  def fetch_channel
    @channel = Current.account.notification_channels.find(params[:id])
  end

  def create_params
    {
      channel_type: params[:channel_type].presence || 'telegram',
      credentials: extract_credentials(params),
      event_filters: params[:event_filters] || NotificationChannel::DEFAULT_EVENT_FILTERS
    }
  end

  def extract_credentials(p)
    {
      'bot_token' => p[:bot_token].to_s,
      'chat_id' => p[:chat_id].to_s
    }.compact_blank
  end

  def serialize(c)
    {
      id: c.id,
      channel_type: c.channel_type,
      status: c.status,
      configured: c.configured?,
      credentials: c.safe_credentials,
      event_filters: c.event_filters.presence || NotificationChannel::DEFAULT_EVENT_FILTERS,
      last_test_status: c.last_test_status,
      last_test_message: c.last_test_message,
      last_test_at: c.last_test_at,
      last_used_at: c.last_used_at,
      failure_count: c.failure_count
    }
  end
end
