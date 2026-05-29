# frozen_string_literal: true

class Api::V1::Accounts::PaymentHandlesController < Api::V1::Accounts::BaseController
  before_action :fetch_payment_handle, except: [:index, :create]
  before_action :check_authorization

  def index
    @handles = policy_scope(Current.account.payment_handles).order(:platform, :priority)
    render json: @handles.as_json(except: [:verification_email_password])
  end

  def create
    @payment_handle = Current.account.payment_handles.new(payment_handle_params)
    if @payment_handle.save
      render json: @payment_handle.as_json(except: [:verification_email_password]), status: :created
    else
      render json: { errors: @payment_handle.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @payment_handle.update(payment_handle_params_for_update)
      render json: @payment_handle.as_json(except: [:verification_email_password])
    else
      render json: { errors: @payment_handle.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @payment_handle.destroy!
    head :ok
  end

  def ledger
    render json: ledger_entries_for(@payment_handle)
  end

  private

  LEDGER_ENTRY_KEYS = %w[
    amount platform sender_name sender_display sender_handle recipient_handle recipient_name transaction_id
    transaction_date transaction_time status confidence source image_received_at image_url
    email_confirmed email_amount email_sender_name email_date email_subject email_from
    email_body_snippet flag_reason resolved_handle resolve_score note_or_memo score_breakdown
  ].freeze

  def ledger_entries_for(payment_handle)
    normalized_handle = payment_handle.normalized_handle
    display_name_words = payment_handle.display_name.to_s.split(/\s+/).map(&:downcase).reject { |word| word.length < 2 }
    matched = []

    Current.account.contacts.where("custom_attributes ? 'patra_finance_logs'").find_each do |contact|
      Array(contact.custom_attributes['patra_finance_logs']).each do |raw|
        entry = raw.is_a?(Hash) ? raw.stringify_keys : next
        next unless ledger_entry_matches?(entry, normalized_handle, display_name_words)

        entry['sender_display'] = entry['sender_name'].presence || "#{contact.name} (FB)" if entry['sender_name'].blank? && contact.name.present?

        matched << entry.slice(*LEDGER_ENTRY_KEYS)
      end
    end

    sorted = matched.sort_by { |entry| ledger_entry_timestamp(entry) || Time.at(0) }.reverse

    sorted.each_with_index do |entry, idx|
      next if entry['flag_reason'] == 'duplicate' || entry['status'] == 'Duplicate'

      sorted[(idx + 1)..].each do |other|
        next unless other['amount'].to_f == entry['amount'].to_f
        next unless other['platform'].to_s == entry['platform'].to_s

        t1 = ledger_entry_timestamp(entry)
        t2 = ledger_entry_timestamp(other)
        next unless t1 && t2 && (t1 - t2).abs < 3600

        other['status'] = 'Duplicate'
        other['flag_reason'] = 'duplicate_ledger'
      end
    end

    sorted.each do |e|
      breakdown = Payments::EmailConfirmationService.confidence_score(e, account: Current.account)
      Rails.logger.info("[Ledger] entry score=#{breakdown['total']} platform=#{e['platform']} keys=#{breakdown.keys.join(',')}")
      e['confidence_score'] = breakdown['total']
      e['score_breakdown'] = breakdown
    end
    sorted.first(50)
  end

  def ledger_entry_matches?(entry, normalized_handle, display_name_words)
    recip = entry['recipient_handle'].to_s.gsub(/^[\$@]/, '').strip.downcase
    return true if recip.present? && recip == normalized_handle

    resolved = entry['resolved_handle'].to_s.gsub(/^[\$@]/, '').strip.downcase
    return true if resolved.present? && resolved == normalized_handle

    recipient_name = entry['recipient_name'].to_s.downcase
    return true if recipient_name.present? && display_name_words.any? { |word| recipient_name.include?(word) }

    sender_name = entry['sender_name'].to_s.downcase
    display_name_words.any? { |word| sender_name.include?(word) }
  end

  def ledger_entry_timestamp(entry)
    raw = entry['transaction_time'].presence || entry['transaction_date'].presence || entry['image_received_at']
    return raw if raw.is_a?(Time) || raw.is_a?(ActiveSupport::TimeWithZone)

    Time.zone.parse(raw.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def fetch_payment_handle
    @payment_handle = policy_scope(Current.account.payment_handles).find(params[:id])
  end

  def payment_handle_params
    params.require(:payment_handle).permit(
      :platform, :handle, :display_name, :priority, :status, :notes,
      :verification_email, :verification_email_password, :verification_email_host,
      :verification_email_port, :verification_email_ssl
    )
  end

  def payment_handle_params_for_update
    permitted = payment_handle_params
    permitted[:verification_email_password].blank? ? permitted.except(:verification_email_password) : permitted
  end
end
