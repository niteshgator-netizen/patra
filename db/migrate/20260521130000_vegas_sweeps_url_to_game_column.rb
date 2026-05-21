class VegasSweepsUrlToGameColumn < ActiveRecord::Migration[7.0]
  def up
    game = Game.find_by(slug: 'vegas_sweeps')
    return unless game

    # Set the Game.api_base_url column directly (clients fall back to this)
    game.update_columns(api_base_url: 'https://apius.lasvegassweeps.com')

    # Remove api_base_url from required_fields so the form stops asking customers for it
    new_fields = (game.required_fields || []).reject { |f| f['name'] == 'api_base_url' }
    game.update_columns(required_fields: new_fields)
    puts "[migration] vegas_sweeps: api_base_url moved to game column, removed from required_fields"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
