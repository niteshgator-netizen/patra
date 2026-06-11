# MEGA2 P6 (Zeitwerk hotfix: own file so the constant autoloads) - raised when
# a panel response AFTER a write cannot be parsed: the write MAY have landed.
# ActionExecutor marks the action 'ambiguous' (never 'failed'), never
# auto-retries, and escalates for a human balance check before any redo.
# Inherits code/payload behavior from Games::ClientError.
module Games
  class AmbiguousPanelStateError < ClientError; end
end
