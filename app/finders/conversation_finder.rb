class ConversationFinder
  attr_reader :current_user, :current_account, :params

  DEFAULT_STATUS = 'open'.freeze
  GROUPS_ASSIGNEE_TYPE = 'groups'.freeze
  HIDEABLE_GROUP_TABS = %w[me unassigned all].freeze
  SORT_OPTIONS = {
    'last_activity_at_asc' => %w[sort_on_last_activity_at asc],
    'last_activity_at_desc' => %w[sort_on_last_activity_at desc],
    'created_at_asc' => %w[sort_on_created_at asc],
    'created_at_desc' => %w[sort_on_created_at desc],
    'priority_asc' => %w[sort_on_priority asc],
    'priority_desc' => %w[sort_on_priority desc],
    'waiting_since_asc' => %w[sort_on_waiting_since asc],
    'waiting_since_desc' => %w[sort_on_waiting_since desc],
    'priority_desc_created_at_asc' => %w[sort_on_priority_created_at desc],

    # To be removed in v3.5.0
    'latest' => %w[sort_on_last_activity_at desc],
    'sort_on_created_at' => %w[sort_on_created_at asc],
    'sort_on_priority' => %w[sort_on_priority desc],
    'sort_on_waiting_since' => %w[sort_on_waiting_since asc]
  }.with_indifferent_access
  # assumptions
  # inbox_id if not given, take from all conversations, else specific to inbox
  # assignee_type if not given, take 'all'
  # conversation_status if not given, take 'open'

  # response of this class will be of type
  # {conversations: [array of conversations], count: {open: count, resolved: count}}

  # params
  # assignee_type, inbox_id, :status

  def initialize(current_user, params)
    @current_user = current_user
    @current_account = current_user.account
    @is_admin = current_account.account_users.find_by(user_id: current_user.id)&.administrator?
    @params = params
  end

  def perform
    set_up

    mine_count, unassigned_count, all_count, group_count = set_count_for_all_conversations
    assigned_count = conversations_for_tab(@conversations.assigned, 'all').count

    filter_by_assignee_type

    {
      conversations: conversations,
      count: {
        mine_count: mine_count,
        assigned_count: assigned_count,
        unassigned_count: unassigned_count,
        all_count: all_count,
        group_count: group_count
      }
    }
  end

  def perform_meta_only
    set_up

    mine_count, unassigned_count, all_count, group_count = set_count_for_all_conversations
    assigned_count = conversations_for_tab(@conversations.assigned, 'all').count

    {
      count: {
        mine_count: mine_count,
        assigned_count: assigned_count,
        unassigned_count: unassigned_count,
        all_count: all_count,
        group_count: group_count
      }
    }
  end

  private

  def set_up
    set_inboxes
    set_team
    set_assignee_type

    find_all_conversations
    filter_by_status unless params[:q] || params[:contact_query].present?
    filter_by_team
    filter_by_labels
    filter_by_query
    filter_by_contact_query
    filter_by_source_id
  end

  def set_inboxes
    @inbox_ids = if params[:inbox_id]
                   @current_user.assigned_inboxes.where(id: params[:inbox_id]).pluck(:id)
                 else
                   @current_user.assigned_inboxes.pluck(:id)
                 end
  end

  def set_assignee_type
    @assignee_type = params[:assignee_type]
  end

  def set_team
    @team = current_account.teams.find(params[:team_id]) if params[:team_id]
  end

  def find_conversation_by_inbox
    @conversations = current_account.conversations.where(inbox_id: @inbox_ids)
  end

  def find_all_conversations
    find_conversation_by_inbox
    # Apply permission-based filtering
    @conversations = Conversations::PermissionFilterService.new(
      @conversations,
      current_user,
      current_account
    ).perform
    filter_by_conversation_type if params[:conversation_type]
    @conversations
  end

  def filter_by_assignee_type
    case @assignee_type
    when 'me'
      @conversations = @conversations.assigned_to(current_user)
    when 'unassigned'
      @conversations = @conversations.unassigned
    when 'assigned'
      @conversations = @conversations.assigned
    when GROUPS_ASSIGNEE_TYPE
      @conversations = group_conversations(@conversations)
      return @conversations
    end
    @conversations = conversations_for_tab(@conversations, @assignee_type)
    @conversations
  end

  def filter_by_conversation_type
    case @params[:conversation_type]
    when 'mention'
      conversation_ids = current_account.mentions.where(user: current_user).pluck(:conversation_id)
      @conversations = @conversations.where(id: conversation_ids)
    when 'participating'
      @conversations = current_user.participating_conversations.where(account_id: current_account.id)
    when 'unattended'
      @conversations = @conversations.unattended
    end
    @conversations
  end

  def filter_by_query
    return unless params[:q]

    allowed_message_types = [Message.message_types[:incoming], Message.message_types[:outgoing]]
    @conversations = conversations.joins(:messages).where('messages.content ILIKE :search', search: "%#{params[:q]}%")
                                  .where(messages: { message_type: allowed_message_types }).includes(:messages)
                                  .where('messages.content ILIKE :search', search: "%#{params[:q]}%")
                                  .where(messages: { message_type: allowed_message_types })
  end

  def filter_by_contact_query
    query = params[:contact_query].to_s.strip
    return if query.blank?

    search = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    conditions = [
      'contacts.name ILIKE :search',
      'contacts.email ILIKE :search',
      'contacts.phone_number ILIKE :search',
      'contacts.identifier ILIKE :search'
    ]
    bindings = { search: search }

    phone_digits = query.delete('^0-9')
    if phone_digits.present?
      conditions << "regexp_replace(COALESCE(contacts.phone_number, ''), '[^0-9]', '', 'g') LIKE :phone_search"
      bindings[:phone_search] = "%#{phone_digits}%"
    end

    @conversations = @conversations.joins(:contact).where(conditions.join(' OR '), bindings)
  end

  def filter_by_status
    return if params[:status] == 'all'

    @conversations = @conversations.where(status: params[:status] || DEFAULT_STATUS)
  end

  def filter_by_team
    return unless @team

    @conversations = @conversations.where(team: @team)
  end

  def filter_by_labels
    return unless params[:labels]

    @conversations = @conversations.tagged_with(params[:labels], any: true)
  end

  def filter_by_source_id
    return unless params[:source_id]

    @conversations = @conversations.joins(:contact_inbox)
    @conversations = @conversations.where(contact_inboxes: { source_id: params[:source_id] })
  end

  def set_count_for_all_conversations
    [
      conversations_for_tab(@conversations.assigned_to(current_user), 'me').count,
      conversations_for_tab(@conversations.unassigned, 'unassigned').count,
      conversations_for_tab(@conversations, 'all').count,
      group_conversations(@conversations).count
    ]
  end

  def conversations_for_tab(relation, tab)
    return relation unless hide_group_tabs.include?(tab.to_s)

    direct_conversations(relation)
  end

  def group_conversations(relation)
    relation.joins(:contact).where("contacts.additional_attributes ->> 'whatsmeow_group' = ?", 'true')
  end

  def direct_conversations(relation)
    relation.joins(:contact).where("COALESCE(contacts.additional_attributes ->> 'whatsmeow_group', 'false') != ?", 'true')
  end

  def hide_group_tabs
    @hide_group_tabs ||= Array(params[:hide_group_tabs]).map(&:to_s) & HIDEABLE_GROUP_TABS
  end

  def current_page
    params[:page] || 1
  end

  def conversations_base_query
    @conversations.includes(
      :taggings, :conversation_pipeline, :conversation_pipeline_stage, :inbox,
      { assignee: { avatar_attachment: [:blob] } },
      { contact: { avatar_attachment: [:blob] } },
      :team, :contact_inbox
    )
  end

  def conversations
    @conversations = conversations_base_query

    sort_by, sort_order = SORT_OPTIONS[params[:sort_by]] || SORT_OPTIONS['last_activity_at_desc']
    @conversations = @conversations.send(sort_by, sort_order)

    if params[:updated_within].present?
      @conversations.where('conversations.updated_at > ?', Time.zone.now - params[:updated_within].to_i.seconds)
    else
      @conversations.page(current_page).per(ENV.fetch('CONVERSATION_RESULTS_PER_PAGE', '25').to_i)
    end
  end
end
ConversationFinder.prepend_mod_with('ConversationFinder')
