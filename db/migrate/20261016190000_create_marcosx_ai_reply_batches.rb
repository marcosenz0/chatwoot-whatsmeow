class CreateMarcosxAiReplyBatches < ActiveRecord::Migration[7.1]
  def change
    create_table :marcosx_ai_reply_batches do |t|
      t.references :account, null: false, foreign_key: true
      t.references :assistant, null: false, foreign_key: { to_table: :marcosx_ai_assistants }
      t.references :user, null: false, foreign_key: true
      t.string :mode, null: false
      t.string :status, null: false, default: 'preparing'
      t.string :request_id, null: false
      t.timestamps
    end
    add_index :marcosx_ai_reply_batches, [:assistant_id, :user_id, :request_id], unique: true, name: 'marcoxia_reply_batch_request'
    create_table :marcosx_ai_reply_batch_items do |t|
      t.references :reply_batch, null: false, foreign_key: { to_table: :marcosx_ai_reply_batches },
                                 index: { name: 'marcoxia_reply_batch_items_batch' }
      t.references :conversation, null: false, foreign_key: true
      t.bigint :trigger_message_id, null: false
      t.string :status, null: false, default: 'pending'
      t.string :assistant_version, null: false
      t.string :run_token
      t.jsonb :plan, null: false, default: {}
      t.string :reason
      t.timestamps
    end
    add_index :marcosx_ai_reply_batch_items, [:conversation_id, :trigger_message_id],
              unique: true, where: "status NOT IN ('discarded', 'failed', 'skipped')",
              name: 'marcoxia_reply_batch_unique_turn'
  end
end
