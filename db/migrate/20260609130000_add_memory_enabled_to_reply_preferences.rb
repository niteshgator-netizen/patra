# frozen_string_literal: true

# Account-level on/off for per-player AI memory (Ai::PlayerMemoryWriter /
# RotatePlayerMemoryJob / reply_service player_memory_lines). Defaults TRUE so
# existing accounts keep current behavior — memory stays on unless an operator
# turns it off in AI settings.
class AddMemoryEnabledToReplyPreferences < ActiveRecord::Migration[7.0]
  def change
    add_column :reply_preferences, :memory_enabled, :boolean, default: true
  end
end
