# frozen_string_literal: true

class Api::V1::Accounts::ReplyPreferencesController < Api::V1::Accounts::BaseController
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
      :confirm_before_load, :confirm_before_cashout, :auto_send_receipt
    )
  end
end
