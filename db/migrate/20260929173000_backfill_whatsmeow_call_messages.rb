class BackfillWhatsmeowCallMessages < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      INSERT INTO messages
        (account_id, inbox_id, conversation_id, message_type, content_type, content,
         source_id, sender_type, sender_id, content_attributes, created_at, updated_at)
      SELECT calls.account_id, calls.inbox_id, calls.conversation_id,
        CASE calls.direction WHEN 'incoming' THEN 0 ELSE 1 END, 12,
        CASE WHEN accounts.locale = 'pt_BR' THEN
          CASE WHEN calls.video THEN 'Ligação de vídeo' ELSE 'Ligação de voz' END
        ELSE CASE WHEN calls.video THEN 'Video call' ELSE 'Voice call' END END,
        'whatsmeow-call:' || calls.source_id,
        CASE calls.direction WHEN 'incoming' THEN 'Contact' ELSE 'User' END,
        CASE calls.direction WHEN 'incoming' THEN calls.contact_id ELSE calls.agent_id END,
        jsonb_build_object('historical', true, 'skip_send_reply_job', true,
          'external_echo', calls.direction = 'outgoing', 'whatsmeow_call', jsonb_build_object(
            'id', calls.id, 'direction', calls.direction, 'status', calls.status, 'video', calls.video,
            'end_reason', calls.end_reason, 'duration_seconds',
            CASE WHEN calls.connected_at IS NULL THEN 0
              ELSE GREATEST(EXTRACT(EPOCH FROM calls.ended_at - calls.connected_at)::integer, 0) END)),
        calls.started_at, CURRENT_TIMESTAMP
      FROM whatsmeow_calls calls JOIN accounts ON accounts.id = calls.account_id
      WHERE calls.ended_at IS NOT NULL AND calls.conversation_id IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM messages
          WHERE messages.inbox_id = calls.inbox_id AND messages.source_id = 'whatsmeow-call:' || calls.source_id)
    SQL
  end

  def down
    # Call records are retained when rolling back the application.
  end
end
