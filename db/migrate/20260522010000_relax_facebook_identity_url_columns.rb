class RelaxFacebookIdentityUrlColumns < ActiveRecord::Migration[7.0]
  def up
    # FB avatar URLs from Graph picture.type(large) routinely exceed 255 chars.
    change_column :facebook_identities, :fb_user_avatar_url, :text
  end

  def down
    change_column :facebook_identities, :fb_user_avatar_url, :string
  end
end
