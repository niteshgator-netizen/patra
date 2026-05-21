class RelaxClusterRequiredFields < ActiveRecord::Migration[7.0]
  CLUSTER_1_SLUGS = %w[milky_way fire_kirin panda_master orion_stars].freeze
  CLUSTER_2_SLUGS = %w[mafia game_room cash_machine mr_all_in_one].freeze

  SIMPLE_REQUIRED_FIELDS = [
    {
      'name'        => 'agent_username',
      'label'       => 'Panel Username',
      'type'        => 'text',
      'help'        => 'Your login username for the game agent panel.',
      'placeholder' => 'e.g. youragentname'
    },
    {
      'name'        => 'agent_password',
      'label'       => 'Panel Password',
      'type'        => 'password',
      'help'        => 'Encrypted at rest. Patra uses this to refresh sessions automatically.',
      'placeholder' => '••••••••'
    }
  ].freeze

  def up
    (CLUSTER_1_SLUGS + CLUSTER_2_SLUGS).each do |slug|
      game = Game.find_by(slug: slug)
      unless game
        puts "[migration] WARN: no game found for slug=#{slug} — skipping"
        next
      end
      old = game.required_fields
      game.update_columns(required_fields: SIMPLE_REQUIRED_FIELDS)
      puts "[migration] #{slug}: was #{old.inspect[0,120]} → now (agent_username, agent_password)"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Restore required_fields manually per game if rollback needed"
  end
end
