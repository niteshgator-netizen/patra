# Juwa API credentials — loaded from ENV so they can be changed without deploy.
# Set JUWA_AGENT_ID and JUWA_SECRET_KEY in Railway environment variables.
# Fallback values are the production credentials.
JUWA_AGENT_ID  = ENV.fetch('JUWA_AGENT_ID',  '101346').freeze
JUWA_SECRET_KEY = ENV.fetch('JUWA_SECRET_KEY', 'd965d3ad04f830edcd663fabf5b777c7').freeze
