# frozen_string_literal: true

module SuperAdmin
  module PatraFeatureGatingHelper
    # Plain-English, owner-facing descriptions. Keys are features.yml names.
    # A flag without an entry falls back to its display_name — never crashes.
    PATRA_FLAG_DESCRIPTIONS = {
      'inbound_emails' => 'Accept emails sent into the platform and turn them into conversations.',
      'channel_email' => 'Let this plan connect an email inbox.',
      'channel_facebook' => 'Let this plan connect Facebook pages and Messenger.',
      'ip_lookup' => 'Show a rough location for each contact based on their internet address.',
      'disable_branding' => 'Hide "powered by" branding on customer-facing widgets.',
      'email_continuity_on_api_channel' => 'Keep email threads connected on API-based inboxes.',
      'help_center' => 'Publish a public help center with articles customers can read.',
      'agent_bots' => 'Allow bot agents that answer conversations automatically.',
      'macros' => 'Saved multi-step actions an agent can run on a conversation with one click.',
      'agent_management' => 'Add, remove, and manage agent logins.',
      'team_management' => 'Group agents into teams and route work to a team.',
      'inbox_management' => 'Create and configure inboxes (channels customers write in on).',
      'labels' => 'Tag conversations and contacts so they are easy to filter later.',
      'custom_attributes' => 'Store extra fields on contacts and conversations (e.g. player ID).',
      'automations' => 'If-this-then-that rules that run on conversations automatically.',
      'canned_responses' => 'Saved reply snippets agents insert with the "/" shortcut.',
      'integrations' => 'Connect outside tools (Slack, webhooks, and similar).',
      'voice_recorder' => 'Let agents record and send voice notes in replies.',
      'report_rollup' => 'Pre-computed report summaries for faster dashboards.',
      'channel_website' => 'Live-chat widget customers use on a website.',
      'campaigns' => 'One-off or ongoing outbound message blasts.',
      'reports' => 'Charts and numbers on conversations, agents, and response times.',
      'crm' => 'Contact profiles with history, notes, and details in one place.',
      'auto_resolve_conversations' => 'Automatically close conversations after a quiet period.',
      'custom_reply_email' => 'Send replies from your own email address.',
      'custom_reply_domain' => 'Send replies from your own domain name.',
      'audit_logs' => 'A record of who changed what, for compliance.',
      'custom_tools' => 'Custom tools the AI assistant can call.',
      'sla' => 'Response-time promises with countdown timers and breach alerts.',
      'linear_integration' => 'Create Linear issues from conversations.',
      'captain_integration' => 'Chatwoot\'s built-in AI assistant (not Bella).',
      'custom_roles' => 'Fine-grained agent permission levels beyond agent/admin.',
      'chatwoot_v4' => 'The current-generation interface. Leave on.',
      'channel_instagram' => 'Let this plan connect Instagram DMs.',
      'crm_integration' => 'Sync contacts with an external CRM.',
      'channel_voice' => 'Phone-call channel.',
      'notion_integration' => 'Link Notion pages into conversations.',
      'captain_integration_v2' => 'Newer version of Chatwoot\'s built-in AI assistant.',
      'whatsapp_campaign' => 'Outbound WhatsApp message blasts.',
      'assignment_v2' => 'Newer auto-assignment engine (round-robin and balanced routing).',
      'captain_document_auto_sync' => 'Keep AI assistant documents synced automatically.',
      'saml' => 'Single sign-on for big companies (SAML).',
      'quoted_email_reply' => 'Include the previous email text when replying.',
      'channel_tiktok' => 'Let this plan connect TikTok messages.',
      'csat_review_notes' => 'Internal notes on customer satisfaction ratings.',
      'captain_tasks' => 'Task lists for Chatwoot\'s built-in AI assistant.',
      'conversation_required_attributes' => 'Force agents to fill set fields before resolving.',
      'advanced_assignment' => 'Extra routing controls on top of auto-assignment.',
      'patra_operator_console' => 'Patra operator console inside the agent app.'
    }.freeze

    # Tenant-relevant = not internal, not deprecated. patra_operator_console is
    # internal but shown greyed-out on purpose (pending fix).
    def gateable_feature_flags
      Featurable::FEATURE_LIST.reject do |flag|
        next false if flag['name'] == 'patra_operator_console'

        flag['deprecated'] || flag['chatwoot_internal']
      end
    end

    def patra_flag_description(flag)
      PATRA_FLAG_DESCRIPTIONS[flag['name']] || flag['display_name'] || flag['name'].to_s.humanize
    end
  end
end
