class Pipelines::BoardBuilder
  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100
  FILTER_KEYS = [:inbox_id, :assignee_id, :team_id, :priority].freeze

  pattr_initialize [:account!, :user!, :pipeline!, :params!]

  def perform
    {
      pipeline: pipeline.push_event_data,
      stages: stage_payloads,
      total_count: base_relation.count
    }
  end

  private

  def stage_payloads
    pipeline.active_stages.map do |stage|
      relation = base_relation.where(conversation_pipeline_stage_id: stage.id)
      current_stage_page = stage_page(stage)
      paginated = relation.order(last_activity_at: :desc).page(1).per(per_page * current_stage_page)

      stage.push_event_data.merge(
        count: relation.count,
        stale_count: stale_count(stage, relation),
        conversations: paginated.map { |conversation| conversation_card(conversation) },
        pagination: {
          current_page: current_stage_page,
          next_page: next_stage_page(relation.count, current_stage_page),
          total_pages: (relation.count.to_f / per_page).ceil
        }
      )
    end
  end

  def base_relation
    @base_relation ||= begin
      relation = account.conversations
                        .where(conversation_pipeline_id: pipeline.id)
                        .includes(
                          :taggings,
                          :conversation_pipeline,
                          :conversation_pipeline_stage,
                          :inbox,
                          { assignee: { avatar_attachment: [:blob] } },
                          { contact: { avatar_attachment: [:blob] } },
                          :team,
                          :contact_inbox
                        )
      relation = Conversations::PermissionFilterService.new(relation, user, account).perform
      relation = apply_filters(relation)
      relation
    end
  end

  def apply_filters(relation)
    relation = relation.where(status: params[:status]) if params[:status].present? && params[:status] != 'all'
    FILTER_KEYS.each do |key|
      relation = relation.where(key => params[key]) if params[key].present?
    end
    relation = relation.tagged_with(params[:labels], any: true) if params[:labels].present?
    apply_query_filter(relation)
  end

  def apply_query_filter(relation)
    return relation if params[:q].blank?

    relation.joins(:messages).where('messages.content ILIKE :search', search: "%#{params[:q]}%").distinct
  end

  def stale_count(stage, relation)
    return 0 if stage.stale_after_days.blank?

    relation.where('pipeline_stage_entered_at < ?', Time.current - stage.stale_after_days.days).count
  end

  def conversation_card(conversation)
    Conversations::EventDataPresenter.new(conversation).push_data.merge(
      uuid: conversation.uuid,
      muted: conversation.muted?,
      pipeline_stage_entered_at: conversation.pipeline_stage_entered_at&.to_i
    )
  end

  def page
    [params[:page].to_i, 1].max
  end

  def stage_pages
    @stage_pages ||= begin
      raw_stage_pages = params[:stage_pages]
      raw_stage_pages = JSON.parse(raw_stage_pages) if raw_stage_pages.is_a?(String)
      raw_stage_pages.presence || {}
    rescue JSON::ParserError
      {}
    end
  end

  def stage_page(stage)
    requested = stage_pages[stage.id.to_s].presence || stage_pages[stage.id].presence || page
    [requested.to_i, 1].max
  end

  def next_stage_page(total_count, current_stage_page)
    total_pages = (total_count.to_f / per_page).ceil
    current_stage_page < total_pages ? current_stage_page + 1 : nil
  end

  def per_page
    requested = params[:per_page].presence&.to_i || DEFAULT_PER_PAGE
    requested.clamp(1, MAX_PER_PAGE)
  end
end
