# frozen_string_literal: true

class CreateGames < ActiveRecord::Migration[7.1]
  def change
    create_table :games do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :logo_emoji
      t.string :logo_url
      t.string :domain
      t.string :player_signup_url
      t.string :agent_login_url
      t.string :api_base_url
      t.boolean :has_api, default: false, null: false
      t.string :api_docs_url
      t.string :auth_method
      t.jsonb :required_fields, default: [], null: false
      t.text :description
      t.string :status, default: 'active', null: false
      t.integer :sort_order, default: 0, null: false
      t.timestamps
    end

    add_index :games, :slug, unique: true
    add_index :games, :status
    add_index :games, :sort_order
  end
end
