class Whatsapp::Automation::RunJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = WhatsappAutomationRun.find_by(id: run_id)
    return if run.blank?

    Whatsapp::Automation::Runner.new(run: run).perform
  end
end
