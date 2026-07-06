class ConversationPipelinePolicy < ApplicationPolicy
  def index?
    administrator? || agent?
  end

  def show?
    index?
  end

  def board?
    index?
  end

  def candidates?
    index?
  end

  def create?
    administrator?
  end

  def update?
    administrator?
  end

  def destroy?
    administrator?
  end

  def reorder_stages?
    administrator?
  end

  private

  def administrator?
    account_user&.administrator?
  end

  def agent?
    account_user&.agent?
  end
end
