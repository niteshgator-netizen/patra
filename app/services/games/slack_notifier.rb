# Sends notifications to Slack via webhook URL.
# Webhook URL configured per-account or via global ENV.

require 'net/http'
require 'uri'
require 'json'

module Games
  class SlackNotifier
    class << self
      def cashout_alert(cashout_request)
        webhook = webhook_url_for(cashout_request.account)
        return { ok: false, reason: 'no webhook configured' } if webhook.blank?

        payload = build_cashout_payload(cashout_request)
        post_to_slack(webhook, payload)
      end

      def load_alert(game_action)
        webhook = webhook_url_for(game_action.account)
        return { ok: false, reason: 'no webhook configured' } if webhook.blank?

        payload = build_load_payload(game_action)
        post_to_slack(webhook, payload)
      end

      private

      def webhook_url_for(account)
        # Account-level override could be added later as a custom_attribute
        ENV['SLACK_CASHOUT_WEBHOOK_URL'].presence
      end

      def build_cashout_payload(cr)
        contact_name = cr.contact&.name || 'Unknown'
        deposit_line = cr.original_deposit ? "$#{cr.original_deposit} via #{cr.deposit_payment_method || 'unknown'}" : 'N/A'
        rules_list = (cr.applied_rules || []).map { |r| "• #{r}" }.join("\n")

        {
          text: "💸 *Cashout Request* — $#{cr.cashout_amount} for #{contact_name}",
          blocks: [
            { type: 'header', text: { type: 'plain_text', text: "💸 Cashout Request — $#{cr.cashout_amount}" } },
            {
              type: 'section',
              fields: [
                { type: 'mrkdwn', text: "*Player:*\n#{contact_name}" },
                { type: 'mrkdwn', text: "*Game username:*\n`#{cr.game_username}`" },
                { type: 'mrkdwn', text: "*Original deposit:*\n#{deposit_line}" },
                { type: 'mrkdwn', text: "*Total points:*\n$#{cr.total_points || 'N/A'}" },
                { type: 'mrkdwn', text: "*Cashout:*\n*$#{cr.cashout_amount}*" },
                { type: 'mrkdwn', text: "*Remaining in game:*\n$#{cr.remaining_points}" }
              ]
            },
            (cr.tip_amount.to_f > 0 ? { type: 'section', text: { type: 'mrkdwn', text: "*Tip:* $#{cr.tip_amount}" } } : nil),
            (cr.reload_amount.to_f > 0 ? { type: 'section', text: { type: 'mrkdwn', text: "*Reload:* $#{cr.reload_amount} back to game" } } : nil),
            {
              type: 'section',
              text: { type: 'mrkdwn', text: "*Pay to:* #{cr.cashout_payment_method || 'TBD'} #{cr.cashout_destination_handle || ''}" }
            },
            (rules_list.present? ? { type: 'section', text: { type: 'mrkdwn', text: "*Applied rules:*\n#{rules_list}" } } : nil),
            { type: 'context', elements: [{ type: 'mrkdwn', text: "Patra · Request ID: #{cr.id}" }] }
          ].compact
        }
      end

      def build_load_payload(action)
        {
          text: "✅ Load executed: $#{action.amount} to #{action.game_username}",
          blocks: [
            {
              type: 'section',
              fields: [
                { type: 'mrkdwn', text: "*Game username:*\n`#{action.game_username}`" },
                { type: 'mrkdwn', text: "*Amount:*\n$#{action.amount}" },
                { type: 'mrkdwn', text: "*Status:*\n#{action.status}" },
                { type: 'mrkdwn', text: "*Method:*\n#{action.payment_method || 'N/A'}" }
              ]
            }
          ]
        }
      end

      def post_to_slack(webhook_url, payload)
        uri = URI(webhook_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.read_timeout = 5
        http.open_timeout = 5

        req = Net::HTTP::Post.new(uri.request_uri, 'Content-Type' => 'application/json')
        req.body = payload.to_json

        response = http.request(req)
        { ok: response.is_a?(Net::HTTPSuccess), status: response.code }
      rescue StandardError => e
        Rails.logger.error("[Slack] notify failed: #{e.message}")
        { ok: false, error: e.message }
      end
    end
  end
end
