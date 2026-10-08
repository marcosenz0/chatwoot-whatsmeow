module PushDataHelper
  extend ActiveSupport::Concern

  def push_event_data
    Conversations::EventDataPresenter.new(self).push_data.merge(marcosx_ai: marcosx_ai_state_data)
  end

  def lock_event_data
    Conversations::EventDataPresenter.new(self).lock_data
  end

  def webhook_data
    Conversations::EventDataPresenter.new(self).webhook_data
  end
end
