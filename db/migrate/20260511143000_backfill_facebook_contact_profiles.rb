# frozen_string_literal: true

class BackfillFacebookContactProfiles < ActiveRecord::Migration[7.1]
  def up
    Facebook::BackfillPlayerProfilesService.new.perform
  end

  def down
    # One-time data backfill; no reverse.
  end
end
