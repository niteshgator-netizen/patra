# frozen_string_literal: true

# ADM5: read-only viewer for the operator audit trail. Routes expose only
# index/show; the model itself raises on update/destroy after persist.
class SuperAdmin::PatraAdminAuditLogsController < SuperAdmin::ApplicationController
  # Newest first by default (Administrate's shared override defaults to id —
  # created_at is indexed and is the contract for "recent admin activity").
  def order
    @order ||= Administrate::Order.new(
      params.fetch(resource_name, {}).fetch(:order, 'created_at'),
      params.fetch(resource_name, {}).fetch(:direction, 'desc')
    )
  end

  def scoped_resource
    PatraAdminAuditLog.all
  end
end
