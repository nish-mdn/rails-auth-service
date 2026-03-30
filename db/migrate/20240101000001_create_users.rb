class CreateUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :users, id: :string, limit: 36 do |t|
      # Devise fields
      t.string :email, null: false, default: ""
      t.string :encrypted_password, null: false, default: ""
      t.string :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :remember_created_at

      # JWT fields
      t.string :jti, null: false

      t.timestamps
    end

    # Add indexes
    add_index :users, :email, unique: true
    add_index :users, :reset_password_token, unique: true
    add_index :users, :jti, unique: true
  end
end
