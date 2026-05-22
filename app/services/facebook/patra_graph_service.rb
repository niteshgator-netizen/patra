# frozen_string_literal: true

# Server-side Graph calls for Patra's Facebook Messenger bridge (OAuth connect,
# page listing, subscriptions, token exchange).
class Facebook::PatraGraphService
  GRAPH_HOST = 'https://graph.facebook.com'
  GRAPH_VERSION = 'v18.0'
  HTTP_TIMEOUT = 15

  class << self
    def exchange_user_token(short_lived_user_token)
      app_id = fb_app_id
      secret = fb_app_secret
      raise ArgumentError, 'FB_APP_ID is not configured' if app_id.blank?
      raise ArgumentError, 'FB_APP_SECRET is not configured' if secret.blank?

      response = HTTParty.get(
        "#{graph_base}/oauth/access_token",
        query: {
          grant_type: 'fb_exchange_token',
          client_id: app_id,
          client_secret: secret,
          fb_exchange_token: short_lived_user_token
        },
        timeout: HTTP_TIMEOUT
      )
      parse_token_response!(response, 'user token exchange')
    end

    def fetch_managed_pages(user_access_token)
      pages = []
      url = "#{graph_base}/me/accounts"
      query = {
        fields: 'id,name,category,picture{url},access_token',
        access_token: user_access_token,
        limit: 100
      }
      use_query = true

      loop do
        response =
          if use_query
            HTTParty.get(url, query: query, timeout: HTTP_TIMEOUT)
          else
            HTTParty.get(url, timeout: HTTP_TIMEOUT)
          end
        raise_graph_error!(response, 'me/accounts') unless response.success?

        body = response.parsed_response
        Array(body['data']).each { |row| pages << normalize_page_row(row) }

        next_url = body.dig('paging', 'next')
        break if next_url.blank?

        url = next_url
        use_query = false
      end

      pages
    end

    def long_lived_page_access_token(page_id, user_access_token)
      response = HTTParty.get(
        "#{graph_base}/#{page_id}",
        query: {
          fields: 'access_token',
          access_token: user_access_token
        },
        timeout: HTTP_TIMEOUT
      )
      parse_token_response!(response, "page #{page_id} long-lived token")
    end

    def subscribe_page_webhook(page_id, page_access_token)
      response = HTTParty.post(
        "#{graph_base}/#{page_id}/subscribed_apps",
        query: {
          subscribed_fields: 'messages,messaging_postbacks,message_echoes',
          access_token: page_access_token
        },
        timeout: HTTP_TIMEOUT
      )
      return true if response.success?

      Rails.logger.warn(
        "[PatraFB] subscribed_apps failed page=#{page_id} http=#{response.code} body=#{response.body}"
      )
      false
    end

    def refresh_page_access_token(page_id, user_long_lived_token)
      long_lived_page_access_token(page_id, user_long_lived_token)
    end

    # Fetches authenticated FB user's profile (id, name, avatar).
    # Called after exchange_user_token to identify which FB user just authorized.
    def fetch_user_profile(user_access_token)
      response = HTTParty.get(
        "#{graph_base}/me",
        query: {
          fields: 'id,name,picture.type(large)',
          access_token: user_access_token
        },
        timeout: HTTP_TIMEOUT
      )
      unless response.success?
        raise StandardError, "FB Graph /me failed: #{response.code} #{response.body.to_s[0, 200]}"
      end

      data = response.parsed_response || {}
      {
        fb_user_id: data['id'].to_s,
        fb_user_name: data['name'].to_s,
        fb_user_avatar_url: data.dig('picture', 'data', 'url').to_s
      }
    rescue StandardError => e
      Rails.logger.warn("[PatraGraphService#fetch_user_profile] #{e.class}: #{e.message.to_s[0, 200]}")
      nil
    end

    private

    def graph_base
      "#{GRAPH_HOST}/#{GRAPH_VERSION}"
    end

    def fb_app_id
      ENV['FB_APP_ID'].presence || GlobalConfigService.load('FB_APP_ID', '')
    end

    def fb_app_secret
      ENV['FB_APP_SECRET'].presence || GlobalConfigService.load('FB_APP_SECRET', '')
    end

    def normalize_page_row(row)
      pic = row['picture']
      picture_url =
        if pic.is_a?(Hash)
          pic.dig('data', 'url') || pic['url']
        end

      {
        id: row['id'].to_s,
        name: row['name'].to_s,
        picture: picture_url.to_s,
        category: row['category'].to_s,
        access_token: row['access_token'].to_s
      }
    end

    def parse_token_response!(response, context)
      raise_graph_error!(response, context) unless response.success?

      token = response.parsed_response.is_a?(Hash) ? response.parsed_response['access_token'] : nil
      raise StandardError, "#{context} returned no access_token" if token.blank?

      token.to_s
    end

    def raise_graph_error!(response, context)
      body = response.parsed_response
      msg = body.is_a?(Hash) ? body['error']&.slice('message', 'code', 'type') : response.body
      raise StandardError, "Facebook Graph error (#{context}): #{msg || response.code}"
    end
  end
end
