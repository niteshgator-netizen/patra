# frozen_string_literal: true

# ADM3: platform-wide integration health matrix (rows = accounts, cols =
# games). READ-ONLY — renders persisted AgentGame state via
# Patra::GameHealthQuery and never triggers a live game connection.
# 🔒 Cells carry status/error text/timestamps only; credentials are never
# read, rendered or transmitted here.
class SuperAdmin::PatraGameHealthController < SuperAdmin::ApplicationController
  def show
    @matrix = Patra::GameHealthQuery.matrix
  end
end
