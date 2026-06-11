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

  # MEGA2 P6 - raised when a panel response AFTER a write cannot be parsed:
  # the write MAY have landed. ActionExecutor marks the action 'ambiguous'
  # (never 'failed'), never auto-retries, and escalates for a human balance
  # check before any redo.
  class AmbiguousPanelStateError < ClientError; end
end
