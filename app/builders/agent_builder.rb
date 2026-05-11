# The AgentBuilder class is responsible for creating a new agent.
# It initializes with necessary attributes and provides a perform method
# to create a user and account user in a transaction.
class AgentBuilder
  # Initializes an AgentBuilder with necessary attributes.
  # @param email [String] the email of the user.
  # @param name [String] the name of the user.
  # @param role [String] the role of the user, defaults to 'agent' if not provided.
  # @param inviter [User] the user who is inviting the agent (Current.user in most cases).
  # @param availability [String] the availability status of the user, defaults to 'offline' if not provided.
  # @param auto_offline [Boolean] the auto offline status of the user.
  pattr_initialize [:email, { name: '' }, :inviter, :account, { role: :agent }, { availability: :offline }, { auto_offline: false }, { password: nil }]

  # Creates a user and account user in a transaction.
  # @return [User] the created user.
  def perform
    ActiveRecord::Base.transaction do
      @user = find_or_create_user
      create_account_user
    end
    @user
  end

  private

  # Finds a user by email or creates a new one.
  #
  # When `password` is supplied, the owner is setting the credential directly
  # (no confirmation email round-trip) so we skip Devise confirmation and the
  # agent can log in immediately. Without a password we still skip the
  # confirmation email — the owner can use the in-app "Send reset password
  # email" or "Set password" flow later — and seed a random password so
  # Devise validations pass.
  # @return [User] the found or created user.
  def find_or_create_user
    user = User.from_email(email)
    return user if user

    @name = email.split('@').first if @name.blank?
    chosen_password = password.presence || "1!aA#{SecureRandom.alphanumeric(12)}"
    new_user = User.new(email: email, name: @name, password: chosen_password, password_confirmation: chosen_password)
    new_user.skip_confirmation!
    new_user.save!
    new_user
  end

  # Checks if the user needs confirmation.
  # @return [Boolean] true if the user is persisted and not confirmed, false otherwise.
  def user_needs_confirmation?
    @user.persisted? && !@user.confirmed?
  end

  # Creates an account user linking the user to the current account.
  def create_account_user
    AccountUser.create!({
      account_id: account.id,
      user_id: @user.id,
      inviter_id: inviter.id
    }.merge({
      role: role,
      availability: availability,
      auto_offline: auto_offline
    }.compact))
  end
end

AgentBuilder.prepend_mod_with('AgentBuilder')
