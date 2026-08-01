class CreateWhatsappCloudAutomationStudio < ActiveRecord::Migration[7.1]
  # Keeping each table definition together makes this migration safer to audit.
  # rubocop:disable Metrics/MethodLength
  def change
    create_whatsapp_automations
    create_whatsapp_automation_runs
    create_whatsapp_campaign_deliveries
  end

  private

  def create_whatsapp_automations
    create_table :whatsapp_automations do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.integer :status, null: false, default: 0
      t.string :trigger_type, null: false, default: 'keyword'
      t.jsonb :trigger_config, null: false, default: {}
      t.jsonb :definition, null: false, default: { nodes: [], edges: [] }
      t.datetime :published_at
      t.timestamps
    end

    add_index :whatsapp_automations, [:account_id, :status]
    add_index :whatsapp_automations, [:inbox_id, :status]
  end

  def create_whatsapp_automation_runs
    create_table :whatsapp_automation_runs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :whatsapp_automation, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.references :conversation, foreign_key: true
      t.integer :status, null: false, default: 0
      t.string :current_node_id
      t.jsonb :context, null: false, default: {}
      t.datetime :next_run_at
      t.text :last_error
      t.timestamps
    end

    add_index :whatsapp_automation_runs, [:status, :next_run_at]
    add_index :whatsapp_automation_runs,
              [:whatsapp_automation_id, :contact_id, :status],
              name: 'idx_whatsapp_runs_on_automation_contact_status'
    add_index :whatsapp_automation_runs,
              [:whatsapp_automation_id, :contact_id],
              unique: true,
              where: 'status IN (0, 1, 2, 3)',
              name: 'idx_unique_unfinished_whatsapp_run'
  end

  def create_whatsapp_campaign_deliveries
    create_table :whatsapp_campaign_deliveries do |t|
      t.references :account, null: false, foreign_key: true
      t.references :campaign, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.references :message, foreign_key: true
      t.integer :status, null: false, default: 0
      t.string :phone_number
      t.string :source_id
      t.string :template_category
      t.string :currency, null: false, default: 'BRL'
      t.decimal :estimated_cost, precision: 12, scale: 4, null: false, default: 0
      # nil means Meta has not returned pricing data yet.
      t.boolean :billable # rubocop:disable Rails/ThreeStateBooleanColumn
      t.string :pricing_model
      t.string :error_code
      t.text :error_message
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :read_at
      t.datetime :failed_at
      t.timestamps
    end

    add_index :whatsapp_campaign_deliveries, [:campaign_id, :contact_id], unique: true,
                                                                          name: 'idx_whatsapp_deliveries_on_campaign_contact'
    add_index :whatsapp_campaign_deliveries, [:campaign_id, :status]
    add_index :whatsapp_campaign_deliveries, :source_id
  end

  # rubocop:enable Metrics/MethodLength
end
