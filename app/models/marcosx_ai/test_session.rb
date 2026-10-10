class MarcosxAi::TestSession < ApplicationRecord
  self.table_name = 'marcosx_ai_test_sessions'
  belongs_to :account
  belongs_to :assistant, class_name: 'MarcosxAi::Assistant'
  belongs_to :user
  validate :same_account

  def processing?
    processing_started_at.present? && processing_started_at > 5.minutes.ago
  end

  def begin_turn!(content:, files: [], event: 'message')
    with_lock do
      raise ArgumentError, 'This test chat is already generating a reply' if processing?

      history = messages.map { |entry| { role: entry.fetch('role'), content: entry['context'] || entry.fetch('content') } }
      update!(title: title.presence || content.truncate(65), processing_started_at: Time.current, turn_token: SecureRandom.uuid, last_error: nil,
              messages: messages + [{ role: 'user', content: content, files: files, event: event }])
      [history, turn_token]
    end
  end

  def complete_turn!(result, token:)
    with_lock do
      return false unless turn_token == token

      entries = messages.deep_dup
      entries.last['context'] = result.fetch(:user_context)
      entries << { role: 'assistant', content: result.fetch(:response), plan: result.fetch(:plan),
                   simulation: result.fetch(:simulation), name: assistant.name }.stringify_keys
      update!(messages: entries, processing_started_at: nil, turn_token: nil, last_error: nil)
      true
    end
  end

  def fail_turn!(error, token:)
    with_lock do
      update!(processing_started_at: nil, turn_token: nil, last_error: error) if turn_token == token
    end
  end

  def public_data(detail: false)
    data = { id: id, title: title, updated_at: updated_at, count: messages.size, processing: processing?, error: last_error }
    detail ? data.merge(messages: messages) : data
  end

  private

  def same_account
    errors.add(:assistant, 'must belong to the account') if assistant && assistant.account_id != account_id
    errors.add(:user, 'must belong to the account') if user && !account.account_users.exists?(user_id: user_id)
  end
end
