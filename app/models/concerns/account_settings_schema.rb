module AccountSettingsSchema
  extend ActiveSupport::Concern

  # it6 — Agent Policy engine. Account-level, agent-configurable bonus/referral/cashout policy stored
  # at account.settings['agent_policy'] (store_accessor :agent_policy on Account). Reused by the Agent
  # Policy settings controller (Lane B) for strong-params shape validation. Optional + null-tolerant
  # everywhere → absent on existing accounts validates clean (NOT in SETTINGS 'required'). Bonuses are
  # an agent-grown ARRAY (names + schedules agent-defined). Resolver (Games::PolicyResolver) reads this.
  AGENT_POLICY_SCHEMA = {
    'type': %w[object null],
    'properties': {
      'bonuses': {
        'type': %w[array null],
        'items': {
          'type': 'object',
          'properties': {
            'id': { 'type': %w[string null] },
            'name': { 'type': %w[string null] },
            'kind': { 'type': %w[string null], 'enum': ['signup', 'deposit', 'custom', nil] },
            'percent': { 'type': %w[number null], 'minimum': 0, 'maximum': 100 },
            'min_deposit': { 'type': %w[number null], 'minimum': 0 },
            'max_deposit': { 'type': %w[number null], 'minimum': 0 },
            'cap': { 'type': %w[number null], 'minimum': 0 },
            'schedule': {
              'type': %w[object null],
              'properties': {
                'mode': { 'type': %w[string null], 'enum': ['always', 'window', nil] },
                'days': { 'type': %w[array null], 'items': { 'type': 'integer', 'minimum': 0, 'maximum': 6 } },
                'start_hm': { 'type': %w[string null] },
                'end_hm': { 'type': %w[string null] }
              },
              'additionalProperties': false
            },
            'active': { 'type': %w[boolean null] }
          },
          'additionalProperties': false
        }
      },
      'referral': {
        'type': %w[object null],
        'properties': {
          'percent': { 'type': %w[number null], 'minimum': 0, 'maximum': 100 },
          'trigger_deposit_number': { 'type': %w[integer null], 'minimum': 1 },
          'cap': { 'type': %w[number null], 'minimum': 0 },
          'active': { 'type': %w[boolean null] }
        },
        'additionalProperties': false
      },
      'cashout': {
        'type': %w[object null],
        'properties': {
          'min': { 'type': %w[number null], 'minimum': 0 },
          'max': { 'type': %w[number null], 'minimum': 0 },
          'playthrough_min': { 'type': %w[number null], 'minimum': 0 },
          'playthrough_max': { 'type': %w[number null], 'minimum': 0 },
          'per_platform': { 'type': %w[object null] },
          'terms_text': { 'type': %w[string null] },
          'active': { 'type': %w[boolean null] }
        },
        'additionalProperties': false
      }
    },
    'additionalProperties': false
  }.freeze

  SETTINGS_PARAMS_SCHEMA = {
    'type': 'object',
    'properties':
      {
        'auto_resolve_after': { 'type': %w[integer null], 'minimum': 10, 'maximum': 1_439_856 },
        'auto_resolve_message': { 'type': %w[string null] },
        'auto_resolve_ignore_waiting': { 'type': %w[boolean null] },
        'audio_transcriptions': { 'type': %w[boolean null] },
        'auto_resolve_label': { 'type': %w[string null] },
        'keep_pending_on_bot_failure': { 'type': %w[boolean null] },
        'captain_auto_resolve_mode': { 'type': %w[string null], 'enum': ['evaluated', 'legacy', 'disabled', nil] },
        'conversation_required_attributes': {
          'type': %w[array null],
          'items': { 'type': 'string' }
        },
        'captain_models': {
          'type': %w[object null],
          'properties': {
            'editor': { 'type': %w[string null] },
            'assistant': { 'type': %w[string null] },
            'copilot': { 'type': %w[string null] },
            'label_suggestion': { 'type': %w[string null] },
            'audio_transcription': { 'type': %w[string null] },
            'help_center_search': { 'type': %w[string null] }
          },
          'additionalProperties': false
        },
        'captain_features': {
          'type': %w[object null],
          'properties': {
            'editor': { 'type': %w[boolean null] },
            'assistant': { 'type': %w[boolean null] },
            'copilot': { 'type': %w[boolean null] },
            'label_suggestion': { 'type': %w[boolean null] },
            'audio_transcription': { 'type': %w[boolean null] },
            'help_center_search': { 'type': %w[boolean null] }
          },
          'additionalProperties': false
        },
        'agent_policy': AGENT_POLICY_SCHEMA
      },
    'required': [],
    'additionalProperties': true
  }.to_json.freeze
end
