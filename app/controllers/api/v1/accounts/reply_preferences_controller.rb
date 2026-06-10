# frozen_string_literal: true

class Api::V1::Accounts::ReplyPreferencesController < Api::V1::Accounts::BaseController
  include Patra::MoneyActionGuard

  # Dark flag (HANDOFF-B-3): reads stay open; mutations admin-only when flag is ON
  # (reply preferences include money-adjacent toggles like confirm_before_cashout).
  before_action :check_money_action_authorization, only: [:update]

  def show
    @pref = ReplyPreference.for_account(Current.account.id)
    render json: @pref
  end

  def update
    @pref = ReplyPreference.for_account(Current.account.id)
    if @pref.update(reply_preference_params)
      render json: @pref
    else
      render json: { errors: @pref.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def reply_preference_params
    params.require(:reply_preference).permit(
      :reply_tone, :use_emojis, :max_reply_lines, :sign_off_text,
      :use_rag_examples, :rag_example_count,
      :confirm_before_load, :confirm_before_cashout, :auto_send_receipt,
      # Automation & Safety (Batch B/C) — transfer, win-back, fraud settings.
      :transfer_mode, :transfer_deposit_shortfall_mode,
      :winback_enabled, :winback_dormant_days_vip,
      :winback_dormant_days_regular, :winback_dormant_days_new,
      :fraud_cashout_velocity_count, :fraud_cashout_velocity_hours,
      :fraud_duplicate_payment_check,
      :payment_reply_source,
      # Per-player AI memory on/off (Batch B mini)
      :memory_enabled
    )
  end
end
