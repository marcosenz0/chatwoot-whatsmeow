module CustomExceptions::Whatsmeow; end

class CustomExceptions::Whatsmeow::InvalidConversationTarget < CustomExceptions::Base
  def message
    @data.to_s
  end
end
