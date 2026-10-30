class CustomExceptions::MarcosxAi < StandardError
  attr_reader :provider_failure, :provider_status, :retry_after

  def initialize(message = nil, provider_failure: false, provider_status: nil, retry_after: nil)
    super(message)
    @provider_failure = provider_failure
    @provider_status = provider_status
    @retry_after = retry_after
  end
end
