class MarcosxAi::Access
  def self.allowed?(user:, conversation:)
    membership = AccountUser.find_by(account: conversation.account, user: user)
    return false unless membership

    ConversationPolicy.new({ user: user, account: conversation.account, account_user: membership }, conversation).show?
  end
end
