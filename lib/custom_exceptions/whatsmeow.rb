module CustomExceptions::Whatsmeow; end

class CustomExceptions::Whatsmeow::InvalidConversationTarget < CustomExceptions::Base
  def message
    @data.to_s
  end
end

class CustomExceptions::Whatsmeow::InvalidPixPayload < CustomExceptions::Base
  def message
    @data.fetch(:message)
  end

  def to_hash
    {
      error: {
        code: @data.fetch(:code),
        message: message
      }
    }
  end

  def http_status
    :unprocessable_entity
  end
end
