class WhatsmeowStickerPolicy < ApplicationPolicy
  def index?
    account_user.present?
  end

  def create?
    account_user.present?
  end

  def destroy?
    account_user.present? && record.user_id == user.id
  end

  def send?
    destroy?
  end
end
