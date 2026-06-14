# frozen_string_literal: true

# Patra (SEC) — admin session management: list a member's active sessions and force-logout.
# Admin-only (check_admin_authorization?), so agents/viewers cannot force anyone out — read-only
# members stay read-only.
class Api::V1::Accounts::Patra::SessionsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :fetch_user

  def index
    render json: { user_id: @user.id, sessions: session_list(@user) }
  end

  # Force-logout EVERY session for the user by clearing their devise-token-auth tokens. The next
  # request on any old token fails auth -> the user is signed out everywhere.
  def destroy
    @user.tokens = {}
    @user.save!
    render json: { user_id: @user.id, sessions: [], forced_logout: true }
  end

  private

  def fetch_user
    @user = Current.account.users.find(params[:user_id])
  end

  def session_list(user)
    (user.tokens || {}).map do |client_id, data|
      data ||= {}
      { client_id: client_id, expiry: safe_time(data['expiry']) }
    end
  end

  def safe_time(unix)
    return nil if unix.blank?

    Time.zone.at(unix.to_i).iso8601
  rescue StandardError
    nil
  end
end
