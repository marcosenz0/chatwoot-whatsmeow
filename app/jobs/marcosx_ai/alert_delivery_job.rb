class MarcosxAi::AlertDeliveryJob < ApplicationJob
  self.queue_adapter = :sidekiq unless Rails.env.test?
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(id)
    delivery = MarcosxAi::AlertDelivery.find(id)
    delivery.with_lock do
      return unless delivery.status == 'pending'

      delivery.update!(attempts: delivery.attempts + 1, last_attempt_at: Time.current)
      alert = delivery.alert
      if delivery.kind == 'panel'
        user = alert.account.users.find(delivery.recipient)
        raise Pundit::NotAuthorizedError unless MarcosxAi::Access.allowed?(user: user, conversation: alert.conversation)

        notification = Notification.create!(account: alert.account, user: user, primary_actor: alert.conversation,
                                            notification_type: :marcosx_ai_attention, meta: { alert_id: alert.id, reason: alert.reason })
        delivery.update!(status: 'sent', notification: notification)
      else
        inbox = alert.account.inboxes.find(alert.configuration.fetch('inbox_id'))
        raise ArgumentError, 'WhatsApp Direct inbox required' unless inbox.channel_type == 'Channel::Whatsmeow'

        conversation = Whatsmeow::DirectConversationBuilder.new(
          inbox: inbox, params: { participant_jid: "#{delivery.recipient.delete_prefix('+')}@s.whatsapp.net" }
        ).perform
        message = conversation.messages.create!(account: alert.account, inbox: inbox, message_type: :outgoing,
                                                sender: alert.assistant, content: MarcosxAi::AlertService.text(alert),
                                                additional_attributes: { marcosx_ai_operational: true, alert_delivery_id: delivery.id })
        delivery.update!(status: 'queued', message: message)
      end
    end
  rescue StandardError => e
    delivery&.with_lock { delivery.update!(status: 'failed', error: e.message.first(500)) }
    if delivery
      MarcosxAi::Log.create!(account: delivery.alert.account, assistant: delivery.alert.assistant, conversation: delivery.alert.conversation,
                             event: 'notification_failed', response: { delivery_id: delivery.id, error: e.class.name })
    end
  end
end
