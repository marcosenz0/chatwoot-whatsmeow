class MarcosxAi::ReplyBatchJob < ApplicationJob
  self.queue_adapter = :sidekiq unless Rails.env.test?
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(id)
    MarcosxAi::ReplyBatchRunner.new(MarcosxAi::ReplyBatch.find(id)).perform
  end
end
