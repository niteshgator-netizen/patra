# frozen_string_literal: true

class CreateHolidays < ActiveRecord::Migration[7.1]
  def change
    create_table :holidays do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :inbox, foreign_key: true, index: true
      t.date :closed_on, null: false
      t.string :name
      t.timestamps
    end

    add_index :holidays, [:account_id, :closed_on]
  end
end
