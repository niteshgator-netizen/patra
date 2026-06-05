class CreateReferrals < ActiveRecord::Migration[7.0]
  def change
    create_table :referrals do |t|
      t.references :account, null: false, foreign_key: true
      t.references :referrer_contact, null: false, foreign_key: { to_table: :contacts }
      t.references :referred_contact, foreign_key: { to_table: :contacts }
      t.string  :status, default: 'pending'
      t.decimal :bonus_amount, precision: 10, scale: 2
      t.string  :bonus_type
      t.datetime :paid_at
      t.timestamps
    end

    add_index :referrals, [:account_id, :referrer_contact_id]
  end
end
