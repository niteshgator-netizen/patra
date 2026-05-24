# frozen_string_literal: true

module Authorization
  class PermissionChecker
    PERMISSIONS = {
      owner: :all,
      administrator: %i[manage_agents manage_settings manage_games reports conversations contacts],
      agent: %i[conversations contacts],
      cashier: %i[conversations manage_players],
      viewer: %i[read_dashboard read_reports]
    }.freeze

    def self.allowed?(user, account, action)
      role = user_role(user, account)
      perms = PERMISSIONS[role.to_sym] || []
      return true if perms == :all

      perms.include?(action.to_sym)
    end

    def self.user_role(user, account)
      account_user = AccountUser.find_by(user: user, account: account)
      return 'agent' unless account_user

      account_user.role
    end
  end
end
