class Api::V1::Accounts::WhatsappCloud::AudienceImportsController < Api::V1::Accounts::WhatsappCloud::BaseController
  def create
    result = Whatsapp::AudienceImportService.new(
      account: Current.account,
      inbox: official_inbox,
      contacts: audience_import_params[:contacts],
      consent_confirmed: audience_import_params[:consent_confirmed],
      default_country_code: audience_import_params[:default_country_code]
    ).perform

    render json: result, status: :created
  rescue Whatsapp::AudienceImportService::Error => e
    render_could_not_create_error(e.message)
  end

  private

  def audience_import_params
    params.permit(:inbox_id, :consent_confirmed, :default_country_code, contacts: [:phone_number, :name, :company_name])
  end
end
