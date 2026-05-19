# Common error class for all HTTP panel clients (Cluster 1 ASP.NET + Cluster 2 Laravel).
# ActionExecutor rescues this in addition to GameVaultError + JuwaError.
module Games
  class ClientError < StandardError
    attr_reader :code, :payload

    def initialize(message, code: nil, payload: nil)
      super(message)
      @code = code
      @payload = payload
    end
  end
end
