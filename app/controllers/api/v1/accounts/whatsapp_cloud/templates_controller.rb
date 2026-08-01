class Api::V1::Accounts::WhatsappCloud::TemplatesController < Api::V1::Accounts::WhatsappCloud::BaseController
  def index
    render json: template_service.list(sync: ActiveModel::Type::Boolean.new.cast(params[:sync]))
  end

  def create
    result = template_service.create!(template_params)
    render json: { result: result, templates: template_service.list[:templates] }, status: :created
  rescue Whatsapp::CloudTemplateService::Error => e
    render_could_not_create_error(e.message)
  end

  def sync
    render json: { templates: template_service.sync!, last_updated_at: Time.current }
  rescue Whatsapp::CloudTemplateService::Error => e
    render_could_not_create_error(e.message)
  end

  def destroy
    result = template_service.delete!(params[:name])
    render json: { result: result, templates: template_service.list[:templates] }
  rescue Whatsapp::CloudTemplateService::Error => e
    render_could_not_create_error(e.message)
  end

  private

  def template_service
    @template_service ||= Whatsapp::CloudTemplateService.new(inbox: official_inbox)
  end

  def template_params
    params.require(:template).permit!
  end
end
