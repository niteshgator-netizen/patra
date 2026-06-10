# Juwa API credentials — loaded from ENV so they can be changed without deploy.
# Set JUWA_AGENT_ID and JUWA_SECRET_KEY in the deploy environment (Render).
# No hardcoded fallbacks: missing ENV means the Juwa client raises at use time.
JUWA_AGENT_ID  = ENV.fetch('JUWA_AGENT_ID', nil).freeze
JUWA_SECRET_KEY = ENV.fetch('JUWA_SECRET_KEY', nil).freeze
