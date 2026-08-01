class AddInboxStatusActivityIndexToConversations < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :conversations,
              [:account_id, :inbox_id, :status, :last_activity_at],
              name: 'index_conversations_on_inbox_status_activity',
              order: { last_activity_at: :desc },
              algorithm: :concurrently,
              if_not_exists: true
  end
end
