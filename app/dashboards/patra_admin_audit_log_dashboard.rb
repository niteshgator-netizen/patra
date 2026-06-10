# frozen_string_literal: true

require 'administrate/base_dashboard'

# ADM5: read-only Administrate dashboard for the operator audit trail.
# FORM_ATTRIBUTES is intentionally empty and routes expose only index/show —
# there is no mutation surface.
class PatraAdminAuditLogDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    admin_user: Field::BelongsTo.with_options(class_name: 'User'),
    action: Field::String,
    target: Field::Polymorphic,
    target_type: Field::String,
    target_id: Field::Number,
    reason: Field::Text,
    metadata: Field::String.with_options(searchable: false),
    ip_address: Field::String,
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    created_at
    admin_user
    action
    target
    reason
    ip_address
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    created_at
    admin_user
    action
    target
    target_type
    target_id
    reason
    metadata
    ip_address
  ].freeze

  FORM_ATTRIBUTES = [].freeze

  COLLECTION_FILTERS = {
    action: ->(resources, attr) { resources.where(action: attr) },
    admin: ->(resources, attr) { resources.where(admin_user_id: attr) },
    since: lambda { |resources, attr|
      time = begin
        Time.zone.parse(attr)
      rescue ArgumentError
        nil
      end
      time ? resources.where(created_at: time..) : resources
    },
    before: lambda { |resources, attr|
      time = begin
        Time.zone.parse(attr)
      rescue ArgumentError
        nil
      end
      time ? resources.where(created_at: ..time) : resources
    }
  }.freeze

  def display_resource(audit_log)
    "Audit ##{audit_log.id} — #{audit_log.action}"
  end
end
