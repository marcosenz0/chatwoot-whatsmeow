# frozen_string_literal: true

FactoryBot.define do
  factory :conversation_pipeline do
    account
    sequence(:name) { |n| "Pipeline #{n}" }
    internal_name { name.parameterize(separator: '_') }
    color { '#2563eb' }
    default { false }

    factory :conversation_pipeline_with_stages do
      after(:create) do |pipeline|
        create(:conversation_pipeline_stage, conversation_pipeline: pipeline, account: pipeline.account, name: 'Novo lead', position: 0)
        create(:conversation_pipeline_stage, conversation_pipeline: pipeline, account: pipeline.account, name: 'Qualificado', position: 1)
      end
    end
  end

  factory :conversation_pipeline_stage do
    conversation_pipeline
    account { conversation_pipeline.account }
    sequence(:name) { |n| "Stage #{n}" }
    internal_name { name.parameterize(separator: '_') }
    color { '#1f93ff' }
    category { 'open' }
    probability { 25 }
    stale_after_days { 2 }
  end
end
