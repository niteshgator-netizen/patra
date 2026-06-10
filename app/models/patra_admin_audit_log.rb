# frozen_string_literal: true

# == Schema Information
#
# Table name: patra_admin_audit_logs
#
#  id            :bigint           not null, primary key
#  admin_user_id :bigint           not null
#  action        :string           not null
#  target_type   :string
#  target_id     :bigint
#  reason        :text
#  metadata      :jsonb            not null, default({})
#  ip_address    :string
#  created_at    :datetime         not null
#
# ADM5: append-only by contract. Rows become readonly the moment they are
# persisted — update/destroy raise ActiveRecord::ReadOnlyRecord. There is no
# updated_at on purpose. Create rows ONLY through Patra::AdminAudit.record
# so metadata passes the credential scrubber.
class PatraAdminAuditLog < ApplicationRecord
  # SuperAdmin is STI on users, so the association resolves through User.
  belongs_to :admin_user, class_name: 'User', optional: true
  belongs_to :target, polymorphic: true, optional: true

  validates :action, presence: true
  validates :admin_user_id, presence: true

  scope :newest_first, -> { order(created_at: :desc) }

  def readonly?
    persisted?
  end

  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'audit logs are append-only' }
end
