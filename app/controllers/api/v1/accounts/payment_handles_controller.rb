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

  private

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
