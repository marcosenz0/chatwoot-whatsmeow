class BackfillWhatsmeowStatusReplyReferences < ActiveRecord::Migration[7.0]
  def up
    execute <<~SQL.squish
      UPDATE messages AS message
      SET content_attributes = jsonb_set(
        COALESCE(message.content_attributes::jsonb, '{}'::jsonb),
        '{whatsmeow_status_reply}',
        jsonb_build_object('id', status.id),
        true
      )::json
      FROM whatsmeow_statuses AS status
      WHERE status.inbox_id = message.inbox_id
        AND status.from_me = TRUE
        AND status.expires_at > CURRENT_TIMESTAMP
        AND message.content_attributes::jsonb ->> 'in_reply_to_external_id' = status.source_id
        AND NOT (COALESCE(message.content_attributes::jsonb, '{}'::jsonb) ? 'whatsmeow_status_reply')
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE messages
      SET content_attributes = (content_attributes::jsonb - 'whatsmeow_status_reply')::json
      WHERE content_attributes::jsonb ? 'whatsmeow_status_reply'
    SQL
  end
end
