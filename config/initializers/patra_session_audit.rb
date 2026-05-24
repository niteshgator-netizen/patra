# frozen_string_literal: true

ActiveSupport::Reloader.to_prepare do
  DeviseOverrides::SessionsController.class_eval do
    after_action :patra_audit_login, only: [:create]
    before_action :patra_audit_logout, only: [:destroy]

    def patra_audit_login
      return unless @resource.present?

      account = @resource.account_users.first&.account
      return unless account

      Audit::Logger.log!(account: account, user: @resource, action: 'login', metadata: { email: @resource.email })
    end

    def patra_audit_logout
      return unless current_user

      account = current_user.account_users.first&.account
      return unless account

      Audit::Logger.log!(account: account, user: current_user, action: 'logout')
    end
  end
end
