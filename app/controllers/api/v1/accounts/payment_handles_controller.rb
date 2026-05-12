# frozen_string_literal: true

class Api::V1::Accounts::PaymentHandlesController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :load_handle, only: [:show, :update, :destroy, :enable, :disable, :reset_failures]

  def index
    @handles = Current.account.payment_handles.order(:platform, :priority)
    render json: @handles.as_json(except: [:verification_email_password])
  end

  def show
    render json: @handle.as_json(except: [:verification_email_password])
  end

  def create
    @handle = Current.account.payment_handles.new(handle_params)
    if @handle.save
      render json: @handle.as_json(except: [:verification_email_password]), status: :created
    else
      render json: { errors: @handle.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @handle.update(handle_params_for_update)
      render json: @handle.as_json(except: [:verification_email_password])
    else
      render json: { errors: @handle.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @handle.destroy
    head :no_content
  end

  def enable
    @handle.update!(status: 'active', cooldown_until: nil, failure_count: 0, last_failure_at: nil)
    render json: @handle.as_json(except: [:verification_email_password])
  end

  def disable
    @handle.update!(status: 'disabled')
    render json: @handle.as_json(except: [:verification_email_password])
  end

  def reset_failures
    @handle.update!(failure_count: 0, last_failure_at: nil)
    render json: @handle.as_json(except: [:verification_email_password])
  end

  private

  def load_handle
    @handle = Current.account.payment_handles.find(params[:id])
  end

  def handle_params
    params.require(:payment_handle).permit(
      :platform, :handle, :display_name, :priority, :status, :notes,
      :verification_email, :verification_email_password, :verification_email_host,
      :verification_email_port, :verification_email_ssl
    )
  end

  def handle_params_for_update
    permitted = handle_params
    if permitted[:verification_email_password].blank?
      permitted = permitted.except(:verification_email_password)
    end
    permitted
  end
end
