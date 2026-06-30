class Api::V1::Accounts::InboxesController < Api::V1::Accounts::BaseController
  include Api::V1::InboxesHelper
  before_action :fetch_inbox, except: [:index, :create]
  before_action :fetch_agent_bot, only: [:set_agent_bot]
  before_action :validate_limit, only: [:create]
  # we are already handling the authorization in fetch inbox
  before_action :check_authorization, except: [:show]

  include Api::V1::Accounts::Concerns::WhatsappHealthManagement

  def index
    @inboxes = policy_scope(Current.account.inboxes)
               .includes(:channel, :portal, :working_hours, { avatar_attachment: :blob })
               .order_by_name
  end

  def show; end

  # Deprecated: This API will be removed in 2.7.0
  def assignable_agents
    @assignable_agents = @inbox.assignable_agents
  end

  def campaigns
    @campaigns = @inbox.campaigns
  end

  def avatar
    @inbox.avatar.attachment.destroy! if @inbox.avatar.attached?
    head :ok
  end

  def create
    ActiveRecord::Base.transaction do
      channel = create_channel
      @inbox = Current.account.inboxes.build(
        {
          name: inbox_name(channel),
          channel: channel
        }.merge(
          permitted_params.except(:channel)
        )
      )
      @inbox.save!
    end
  end

  def update
    inbox_params = permitted_params.except(:channel, :csat_config)
    inbox_params[:csat_config] = format_csat_config(permitted_params[:csat_config]) if permitted_params[:csat_config].present?
    @inbox.update!(inbox_params)
    update_inbox_working_hours
    update_channel if channel_update_required?
  end

  def agent_bot
    @agent_bot = @inbox.agent_bot
  end

  def set_agent_bot
    if @agent_bot
      agent_bot_inbox = @inbox.agent_bot_inbox || AgentBotInbox.new(inbox: @inbox)
      agent_bot_inbox.agent_bot = @agent_bot
      agent_bot_inbox.save!
    elsif @inbox.agent_bot_inbox.present?
      @inbox.agent_bot_inbox.destroy!
    end
    head :ok
  end

  def reset_secret
    return head :not_found unless @inbox.api?

    @inbox.channel.reset_secret!
  end

  def whatsmeow_session
    handle_whatsmeow_session do |client|
      client.create(force_new: force_new_whatsmeow_session?)
    end
  end

  def whatsmeow_status
    handle_whatsmeow_session(&:status)
  end

  def whatsmeow_groups
    return head :not_found unless @inbox.channel_type == 'Channel::Whatsmeow'

    render json: Whatsmeow::SessionClient.new(inbox: @inbox).groups
  rescue Whatsmeow::SessionClient::Error => e
    render json: { message: e.message }, status: :bad_gateway
  end

  def whatsmeow_group_members
    return head :not_found unless @inbox.channel_type == 'Channel::Whatsmeow'

    group_jid = params[:group_jid].presence
    return render json: { message: 'group_jid is required' }, status: :bad_request if group_jid.blank?

    render json: Whatsmeow::SessionClient.new(inbox: @inbox).group_members(group_jid)
  rescue Whatsmeow::SessionClient::Error => e
    render json: { message: e.message }, status: :bad_gateway
  end

  def whatsmeow_group_member
    return head :not_found unless @inbox.channel_type == 'Channel::Whatsmeow'

    group_jid = params[:group_jid].presence
    participant_jid = params[:participant_jid].presence
    participant_phone = params[:participant_phone].presence
    return render json: { message: 'group_jid is required' }, status: :bad_request if group_jid.blank?

    if participant_jid.blank? && participant_phone.blank?
      return render json: { message: 'participant_jid or participant_phone is required' }, status: :bad_request
    end

    render json: Whatsmeow::SessionClient.new(inbox: @inbox).add_group_member(
      group_jid: group_jid,
      participant_jid: participant_jid,
      participant_phone: participant_phone
    )
  rescue Whatsmeow::SessionClient::Error => e
    render json: { message: e.message }, status: :bad_gateway
  end

  def whatsmeow_group_conversation
    return head :not_found unless @inbox.channel_type == 'Channel::Whatsmeow'

    conversation = Whatsmeow::GroupConversationBuilder.new(
      inbox: @inbox,
      params: whatsmeow_group_conversation_params
    ).perform
    render json: {
      id: conversation.display_id,
      conversation_id: conversation.display_id,
      display_id: conversation.display_id,
      contact_id: conversation.contact_id
    }
  rescue ArgumentError => e
    render json: { message: e.message }, status: :bad_request
  end

  def whatsmeow_direct_conversation
    return head :not_found unless @inbox.channel_type == 'Channel::Whatsmeow'

    conversation = Whatsmeow::DirectConversationBuilder.new(
      inbox: @inbox,
      params: whatsmeow_direct_conversation_params
    ).perform
    render json: {
      id: conversation.display_id,
      conversation_id: conversation.display_id,
      display_id: conversation.display_id,
      contact_id: conversation.contact_id
    }
  rescue ArgumentError => e
    render json: { message: e.message }, status: :bad_request
  end

  def destroy_whatsmeow_session
    handle_whatsmeow_session(&:disconnect)
  end

  def destroy
    ::DeleteObjectJob.perform_later(@inbox, Current.user, request.ip) if @inbox.present?
    render status: :ok, json: { message: I18n.t('messages.inbox_deletetion_response') }
  end

  private

  def handle_whatsmeow_session
    return head :not_found unless @inbox.channel_type == 'Channel::Whatsmeow'

    payload = yield Whatsmeow::SessionClient.new(inbox: @inbox)
    update_whatsmeow_status(payload)
    render json: payload
  rescue Whatsmeow::SessionClient::Error => e
    render json: { message: e.message }, status: :bad_gateway
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:id])
    authorize @inbox, :show?
  end

  def fetch_agent_bot
    @agent_bot = AgentBot.accessible_to(Current.account).find(params[:agent_bot]) if params[:agent_bot]
  end

  def create_channel
    return unless allowed_channel_types.include?(permitted_params[:channel][:type])

    account_channels_method.create!(permitted_params(channel_type_from_params::EDITABLE_ATTRS)[:channel].except(:type))
  end

  def allowed_channel_types
    %w[web_widget api email line telegram whatsapp sms whatsmeow]
  end

  def update_inbox_working_hours
    @inbox.update_working_hours(params.permit(working_hours: Inbox::OFFISABLE_ATTRS)[:working_hours]) if params[:working_hours]
  end

  def update_channel
    channel_attributes = get_channel_attributes(@inbox.channel_type)
    return if permitted_params(channel_attributes)[:channel].blank?

    validate_and_update_email_channel(channel_attributes) if @inbox.inbox_type == 'Email'

    reauthorize_and_update_channel(channel_attributes)
    update_channel_feature_flags
  end

  def channel_update_required?
    permitted_params(get_channel_attributes(@inbox.channel_type))[:channel].present?
  end

  def validate_and_update_email_channel(channel_attributes)
    validate_email_channel(channel_attributes)
  rescue StandardError => e
    render json: { message: e }, status: :unprocessable_entity and return
  end

  def reauthorize_and_update_channel(channel_attributes)
    @inbox.channel.reauthorized! if @inbox.channel.respond_to?(:reauthorized!)
    @inbox.channel.update!(permitted_params(channel_attributes)[:channel])
  end

  def update_channel_feature_flags
    return unless @inbox.web_widget?
    return unless permitted_params(Channel::WebWidget::EDITABLE_ATTRS)[:channel].key? :selected_feature_flags

    @inbox.channel.selected_feature_flags = permitted_params(Channel::WebWidget::EDITABLE_ATTRS)[:channel][:selected_feature_flags]
    @inbox.channel.save!
  end

  def update_whatsmeow_status(payload)
    status = payload['status'].presence
    phone_number = payload['phone_number'].presence
    updates = {}
    updates[:status] = status if status.present? && @inbox.channel.status != status
    updates[:phone_number] = phone_number if phone_number.present? && @inbox.channel.phone_number != phone_number
    @inbox.channel.update!(updates) if updates.present?
  end

  def format_csat_config(config)
    formatted = {
      'display_type' => config['display_type'] || 'emoji',
      'message' => config['message'] || '',
      :survey_rules => {
        'operator' => config.dig('survey_rules', 'operator') || 'contains',
        'values' => config.dig('survey_rules', 'values') || []
      },
      'button_text' => config['button_text'] || 'Please rate us',
      'language' => config['language'] || 'en'
    }
    format_template_config(config, formatted)
    formatted
  end

  def format_template_config(config, formatted)
    formatted['template'] = config['template'] if config['template'].present?
  end

  def inbox_attributes
    [:name, :avatar, :greeting_enabled, :greeting_message, :enable_email_collect, :csat_survey_enabled,
     :enable_auto_assignment, :working_hours_enabled, :out_of_office_message, :timezone, :allow_messages_after_resolved,
     :lock_to_single_conversation, :portal_id, :sender_name_type, :business_name,
     { csat_config: [:display_type, :message, :button_text, :language,
                     { survey_rules: [:operator, { values: [] }],
                       template: [:name, :template_id, :friendly_name, :content_sid, :approval_sid, :created_at, :language, :status] }] }]
  end

  def permitted_params(channel_attributes = [])
    # We will remove this line after fixing https://linear.app/chatwoot/issue/CW-1567/null-value-passed-as-null-string-to-backend
    params.each { |k, v| params[k] = params[k] == 'null' ? nil : v }
    params.permit(*inbox_attributes, channel: [:type, *channel_attributes])
  end

  def whatsmeow_direct_conversation_params
    params.permit(:participant_jid, :participant_lid_jid, :participant_phone, :participant_name, :profile_picture_url)
  end

  def whatsmeow_group_conversation_params
    params.permit(:group_jid, :group_name, :profile_picture_url, :participant_count)
  end

  def force_new_whatsmeow_session?
    ActiveModel::Type::Boolean.new.cast(params[:force_new])
  end

  def channel_type_from_params
    {
      'web_widget' => Channel::WebWidget,
      'api' => Channel::Api,
      'email' => Channel::Email,
      'line' => Channel::Line,
      'telegram' => Channel::Telegram,
      'whatsapp' => Channel::Whatsapp,
      'sms' => Channel::Sms,
      'whatsmeow' => Channel::Whatsmeow
    }[permitted_params[:channel][:type]]
  end

  def get_channel_attributes(channel_type)
    channel_type.constantize.const_defined?(:EDITABLE_ATTRS) ? channel_type.constantize::EDITABLE_ATTRS.presence : []
  end
end

Api::V1::Accounts::InboxesController.prepend_mod_with('Api::V1::Accounts::InboxesController')
