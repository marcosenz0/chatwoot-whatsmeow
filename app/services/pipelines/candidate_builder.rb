class Pipelines::CandidateBuilder
  DEFAULT_PER_PAGE = 20
  MAX_PER_PAGE = 50

  pattr_initialize [:account!, :user!, :pipeline!, :params!]

  def perform
    paginated = relation.page(page).per(per_page)

    {
      conversations: paginated.map { |conversation| conversation_card(conversation) },
      meta: {
        current_page: page,
        count: paginated.total_count,
        next_page: paginated.next_page
      }
    }
  end

  private

  def relation
    @relation ||= begin
      records = candidate_relation
      records = Conversations::PermissionFilterService.new(records, user, account).perform
      records = apply_status_filter(records)
      records = exclude_groups(records) unless include_groups?
      records = apply_query_filter(records)
      records.order(last_activity_at: :desc)
    end
  end

  def candidate_relation
    account.conversations
           .left_joins(:contact)
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
           .where(
             'conversations.conversation_pipeline_id IS NULL OR conversations.conversation_pipeline_id != ?',
             pipeline.id
           )
  end

  def apply_status_filter(records)
    return records if params[:status].blank? || params[:status] == 'all'

    records.where(status: params[:status])
  end

  def apply_query_filter(records)
    return records if search_query.blank?

    records.left_joins(:messages).where(
      "cast(conversations.display_id as text) ILIKE :search
        OR contacts.name ILIKE :search
        OR contacts.email ILIKE :search
        OR contacts.phone_number ILIKE :search
        OR contacts.identifier ILIKE :search
        OR messages.content ILIKE :search",
      search: "%#{search_query}%"
    ).distinct
  end

  def exclude_groups(records)
    records.where("contacts.additional_attributes ->> 'whatsmeow_group' IS DISTINCT FROM ?", 'true')
  end

  def conversation_card(conversation)
    Conversations::EventDataPresenter.new(conversation).push_data.merge(
      uuid: conversation.uuid,
      muted: conversation.muted?,
      is_group: group_conversation?(conversation),
      pipeline_stage_entered_at: conversation.pipeline_stage_entered_at&.to_i
    )
  end

  def group_conversation?(conversation)
    conversation.contact&.additional_attributes&.with_indifferent_access&.fetch(
      :whatsmeow_group,
      false
    ).in?([true, 'true'])
  end

  def include_groups?
    ActiveModel::Type::Boolean.new.cast(params[:include_groups])
  end

  def search_query
    params[:q].to_s.strip
  end

  def page
    [params[:page].to_i, 1].max
  end

  def per_page
    requested = params[:per_page].presence&.to_i || DEFAULT_PER_PAGE
    requested.clamp(1, MAX_PER_PAGE)
  end
end
