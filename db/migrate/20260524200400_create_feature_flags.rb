# frozen_string_literal: true

class CreateFeatureFlags < ActiveRecord::Migration[7.1]
  def change
    create_table :feature_flags do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :enabled_globally, default: false, null: false
      t.integer :enabled_for_accounts, array: true, default: []
      t.integer :percentage_rollout, default: 0, null: false
      t.timestamps
    end

    add_index :feature_flags, :name, unique: true
  end
end
