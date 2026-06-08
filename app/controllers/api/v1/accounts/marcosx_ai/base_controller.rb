class Api::V1::Accounts::MarcosxAi::BaseController < Api::V1::Accounts::BaseController
  private

  def ensure_admin!
    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?
  end

  def account_preferences
    (Current.account.marcosx_ai_preferences || {}).with_indifferent_access
  end

  def save_account_preferences!(preferences)
    Current.account.marcosx_ai_preferences = account_preferences.deep_merge(preferences.with_indifferent_access)
    Current.account.save!
  end
end
