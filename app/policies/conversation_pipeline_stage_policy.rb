class ConversationPipelineStagePolicy < ApplicationPolicy
  def create?
    administrator?
  end

  def update?
    administrator?
  end

  def destroy?
    administrator?
  end

  def reorder?
    administrator?
  end

  private

  def administrator?
    account_user&.administrator?
  end
end
