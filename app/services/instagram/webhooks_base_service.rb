class Instagram::WebhooksBaseService
  attr_reader :channel

  def initialize(channel)
    @channel = channel
  end

  private

  def inbox_channel(_instagram_id)
    @inbox = ::Inbox.find_by(channel: @channel)
  end

  def find_or_create_contact(user)
    @contact_inbox = @inbox.contact_inboxes.where(source_id: user['id']).first
    @contact = @contact_inbox.contact if @contact_inbox

    unless @contact
      @contact_inbox = @inbox.channel.create_contact_inbox(
        user['id'], user['name']
      )
      @contact = @contact_inbox.contact
    end

    update_instagram_profile_link(user)
    return unless user['profile_pic'].present? && contact_avatar_missing?(@contact)

    Avatar::AvatarFromUrlJob.perform_later(@contact, user['profile_pic'], force: true)
  end

  def contact_avatar_missing?(contact)
    avatar = contact.avatar
    !avatar.attached? || !avatar.blob.service.exist?(avatar.blob.key)
  end

  def update_instagram_profile_link(user)
    return unless user['username']

    instagram_attributes = build_instagram_attributes(user)
    @contact.update!(additional_attributes: @contact.additional_attributes.merge(instagram_attributes))
  end

  def build_instagram_attributes(user)
    attributes = {
      # TODO: Remove this once we show the social_instagram_user_name in the UI instead of the username
      'social_profiles': { 'instagram': user['username'] },
      'social_instagram_user_name': user['username']
    }

    # Add optional attributes if present
    optional_fields = %w[
      follower_count
      is_user_follow_business
      is_business_follow_user
      is_verified_user
    ]

    optional_fields.each do |field|
      next if user[field].nil?

      attributes["social_instagram_#{field}"] = user[field]
    end

    attributes
  end
end
