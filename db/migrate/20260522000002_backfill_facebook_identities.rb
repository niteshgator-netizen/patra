class BackfillFacebookIdentities < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    say_with_time 'Backfilling FacebookIdentity for existing FB-bridge Channel::Api inboxes' do
      created_count = 0
      linked_count = 0

      ::Channel::Api.find_each do |channel|
        attrs = channel.additional_attributes
        next unless attrs.is_a?(Hash)

        page_id = attrs['fb_page_id']
        user_token = attrs['fb_user_long_lived_token']
        next if page_id.blank? || user_token.blank?
        next if channel.facebook_identity_id.present?

        identity = FacebookIdentity.find_or_create_by!(
          account_id: channel.account_id,
          fb_user_id: "backfilled_#{Digest::SHA256.hexdigest(user_token)[0, 16]}"
        ) do |fi|
          fi.fb_user_name = "Backfilled FB Account (#{Time.current.to_date})"
          fi.user_access_token = user_token
          fi.token_expires_at = 50.days.from_now
          fi.token_last_refreshed_at = Time.current
          fi.status = 'active'
          created_count += 1
        end

        channel.update_columns(facebook_identity_id: identity.id)
        linked_count += 1
      end

      puts "[backfill] created identities: #{created_count}"
      puts "[backfill] linked channels: #{linked_count}"
    end
  end

  def down
    ::Channel::Api.where.not(facebook_identity_id: nil).update_all(facebook_identity_id: nil)
  end
end
