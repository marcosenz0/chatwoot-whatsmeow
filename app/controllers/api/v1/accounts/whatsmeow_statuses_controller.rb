require 'digest'

class Api::V1::Accounts::WhatsmeowStatusesController < Api::V1::Accounts::BaseController
  include Whatsmeow::StatusPayloadable

  before_action :set_inbox, only: [:index]
  before_action :set_inboxes, only: [:create]
  before_action :set_status, only: [:view, :reply, :viewers, :preview, :retry, :destroy]

  def index
    statuses = @inbox.whatsmeow_statuses.active
                     .includes(:created_by, { contact: { avatar_attachment: :blob } }, media_attachment: :blob)
                     .order(:posted_at).to_a
    viewed_status_ids = Current.user.whatsmeow_status_views
                               .where(whatsmeow_status_id: statuses.map(&:id))
                               .pluck(:whatsmeow_status_id)
                               .index_with(true)
    viewer_counts = status_viewer_counts(statuses)
    render json: { payload: statuses.map { |status| status_payload(status, viewed_status_ids, viewer_counts) } }
  end

  def create
    statuses = Whatsmeow::StatusPublicationScheduler.new(inboxes: @inboxes, user: Current.user, params: publication_params).perform
    payload = if legacy_single_inbox_request?
                status_payload(statuses.first, {})
              else
                statuses.map { |status| status_payload(status, {}) }
              end
    render json: { payload: payload }, status: :accepted
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render json: { message: e.message }, status: :unprocessable_entity
  end

  def view
    Whatsmeow::StatusViewService.new(status: @status, user: Current.user).perform
    render json: { payload: status_payload(@status.reload, @status.id => true) }
  end

  def reply
    response = Whatsmeow::StatusReplyService.new(
      status: @status,
      params: reply_params,
      sticker: reply_sticker
    ).perform
    render json: { payload: response }
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render json: { message: e.message }, status: :unprocessable_entity
  rescue Whatsmeow::SessionClient::Error => e
    render json: { message: e.message }, status: :bad_gateway
  end

  def viewers
    return head :not_found unless owned_status_inbox(@status)

    viewers = @status.status_viewers
                     .includes(contact: { avatar_attachment: :blob })
                     .order(viewed_at: :desc)
                     .to_a
                     .uniq(&:identity_key)
    render json: {
      payload: viewers.map { |viewer| status_viewer_payload(viewer, @status) },
      meta: { count: viewers.size }
    }
  end

  def preview
    status_inbox = owned_status_inbox(@status)
    return head :not_found unless status_inbox

    viewer_counts = { @status.id => @status.status_viewers.to_a.uniq(&:identity_key).size }
    payload = status_payload(@status, {}, viewer_counts)
    payload[:inbox_name] = status_inbox.name
    render json: { payload: payload }
  end

  def retry
    leader = reset_failed_publication
    return render json: { message: 'Only failed Status publications can be retried' }, status: :unprocessable_entity if leader.blank?

    Whatsmeow::PublishStatusJob.perform_later(leader.id)
    render json: { payload: status_payload(@status.reload, {}) }, status: :accepted
  end

  def destroy
    status_inbox = owned_status_inbox(@status)
    return head :not_found unless status_inbox

    unless destroy_publication_delivery(status_inbox)
      return render json: { message: 'Wait for the Status publication to finish before deleting it' }, status: :conflict
    end

    head :no_content
  rescue Whatsmeow::SessionClient::Error => e
    render json: { message: e.message }, status: :bad_gateway
  end

  private

  def set_inbox
    @inbox = policy_scope(Current.account.inboxes).find(params.require(:inbox_id))
    authorize @inbox, :show?
    head :not_found if @inbox.channel_type != 'Channel::Whatsmeow'
  end

  def set_inboxes
    ids = requested_inbox_ids
    inboxes = accessible_inboxes(ids)

    @inboxes = ids.map { |id| inboxes.fetch(id) }
    @inboxes.each { |inbox| validate_publishable_inbox!(inbox) }
  end

  def requested_inbox_ids
    values = Array(params[:inbox_ids]).presence || Array(params[:inbox_id])
    values.compact_blank.map(&:to_i).uniq
  end

  def accessible_inboxes(ids)
    inboxes = policy_scope(Current.account.inboxes).includes(:channel).where(id: ids).index_by(&:id)
    raise ActiveRecord::RecordNotFound unless ids.present? && inboxes.size == ids.size

    inboxes
  end

  def validate_publishable_inbox!(inbox)
    authorize inbox, :whatsmeow_status?
    return if inbox.channel_type == 'Channel::Whatsmeow' && inbox.channel.status == 'connected'

    raise ActiveRecord::RecordNotFound
  end

  def set_status
    @status = Current.account.whatsmeow_statuses.active.find(params[:id])
    authorize @status.inbox, %w[reply retry destroy].include?(action_name) ? :whatsmeow_status? : :show?
  end

  def status_params
    params.permit(:inbox_id, :publication_id, :content, :media, :background, :font, inbox_ids: [])
  end

  def publication_params
    permitted = status_params.to_h.symbolize_keys
    return permitted unless legacy_single_inbox_request?

    permitted.merge(publication_id: legacy_publication_id, legacy_single_inbox: true)
  end

  def legacy_single_inbox_request?
    params[:inbox_ids].blank? && params[:inbox_id].present?
  end

  def legacy_publication_id
    original_id = status_params[:publication_id].presence
    return if original_id.blank?

    digest = Digest::SHA256.hexdigest([Current.account.id, original_id, legacy_session_key].join(':'))
    "#{digest[0, 8]}-#{digest[8, 4]}-5#{digest[13, 3]}-a#{digest[17, 3]}-#{digest[20, 12]}"
  end

  def legacy_session_key
    inbox = @inboxes.first
    phone = inbox.channel.phone_number.to_s.delete('^0-9')
    phone.present? ? "phone:#{phone}" : "inbox:#{inbox.id}"
  end

  def reply_params
    params.permit(:content, :reaction, :sticker_id)
  end

  def reply_sticker
    return if reply_params[:sticker_id].blank?

    Current.user.whatsmeow_stickers.where(account_id: Current.account.id).find(reply_params[:sticker_id])
  end

  def publication_delivery_scope(status)
    return Current.account.whatsmeow_statuses.where(id: status.id) if status.publication_id.blank? || status.session_key.blank?

    Current.account.whatsmeow_statuses.where(publication_id: status.publication_id, session_key: status.session_key)
  end

  def destroy_publication_delivery(status_inbox)
    deleted = false
    WhatsmeowStatus.transaction do
      statuses = publication_delivery_scope(@status).lock.to_a
      next if statuses.any?(&:publication_processing?)

      delete_published_status(status_inbox, statuses)
      statuses.each(&:destroy!)
      deleted = true
    end
    deleted
  end

  def delete_published_status(status_inbox, statuses)
    return unless statuses.any? { |status| status.publication_published? || status.publish_attempts.positive? }

    Whatsmeow::SessionClient.new(inbox: status_inbox).delete_status(@status.source_id)
  end

  def reset_failed_publication
    leader = nil
    WhatsmeowStatus.transaction do
      statuses = publication_delivery_scope(@status).lock.to_a
      next unless statuses.present? && statuses.all?(&:publication_failed?)

      statuses.each { |status| reset_publication_delivery(status) }
      leader = statuses.min_by(&:id)
    end
    leader
  end

  def reset_publication_delivery(status)
    status.update!(
      publication_state: :queued,
      publish_attempts: 0,
      last_error: nil,
      next_attempt_at: nil
    )
  end
end
