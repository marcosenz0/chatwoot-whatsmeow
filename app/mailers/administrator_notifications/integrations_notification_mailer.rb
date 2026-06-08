class AdministratorNotifications::IntegrationsNotificationMailer < AdministratorNotifications::BaseMailer
  def slack_disconnect
    subject = 'Sua integração com o Slack expirou'
    action_url = settings_url('integrations/slack')
    send_notification(subject, action_url: action_url)
  end

  def dialogflow_disconnect
    subject = 'Sua integração com o Dialogflow foi desconectada'
    send_notification(subject)
  end

  def openai_disconnect
    subject = 'Sua integração com a OpenAI foi desconectada'
    action_url = settings_url('integrations/openai')
    send_notification(subject, action_url: action_url)
  end
end
