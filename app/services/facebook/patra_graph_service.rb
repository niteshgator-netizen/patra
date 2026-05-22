# frozen_string_literal: true

# Server-side Graph calls for Patra's Facebook Messenger bridge (OAuth connect,
# page listing, subscriptions, token exchange).
class Facebook::PatraGraphService
  GRAPH_HOST = 'https://graph.facebook.com'
  GRAPH_VERSION = 'v18.0'
  HTTP_TIMEOUT = 15

  class << self
    def exchange_oauth_code(code:, redirect_uri:, app_id:, app_secret:)
      resolved_id, resolved_secret = resolve_app_credentials(app_id, app_secret)

      response = HTTParty.get(
        "#{graph_base}/oauth/access_token",
        query: {
          client_id: resolved_id,
          client_secret: resolved_secret,
          redirect_uri: redirect_uri,
          code: code
        },
        timeout: HTTP_TIMEOUT
      )
      parse_token_response!(response, 'oauth code exchange')
    end

    def exchange_user_token(short_lived_user_token, app_id: nil, app_secret: nil)
      resolved_id, resolved_secret = resolve_app_credentials(app_id, app_secret)

      response = HTTParty.get(
        "#{graph_base}/oauth/access_token",
        query: {
          grant_type: 'fb_exchange_token',
          client_id: resolved_id,
          client_secret: resolved_secret,
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

    def subscribe_page_webhook(page_id, page_access_token, app_id: nil, app_secret: nil)
      _resolved_id, _resolved_secret = resolve_app_credentials(app_id, app_secret)
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

    # Resolves a page access token from /me/accounts, falling back to page-scoped Graph.
    def fetch_page_access_token(user_access_token, page_id)
      page_id = page_id.to_s
      pages = fetch_managed_pages(user_access_token)
      match = pages.find { |p| p[:id].to_s == page_id }
      token = match&.dig(:access_token).presence
      return token if token.present?

      long_lived_page_access_token(page_id, user_access_token)
    rescue StandardError => e
      Rails.logger.warn("[PatraGraphService#fetch_page_access_token] #{e.class}: #{e.message}")
      nil
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

    def fetch_page_conversations(page_id:, page_access_token:, limit: 50)
      rows = fetch_paginated_graph_data(
        url: "#{graph_base}/#{page_id}/conversations",
        query: {
          fields: 'id,updated_time,participants',
          access_token: page_access_token,
          limit: 25
        },
        limit: limit,
        context: "page #{page_id} conversations"
      )
      rows.map { |row| normalize_conversation_row(row) }
    end

    def fetch_conversation_messages(conversation_id:, page_access_token:, limit: 25)
      rows = fetch_paginated_graph_data(
        url: "#{graph_base}/#{conversation_id}/messages",
        query: {
          fields: 'id,created_time,from,to,message',
          access_token: page_access_token,
          limit: 25
        },
        limit: limit,
        context: "conversation #{conversation_id} messages"
      )
      rows.map { |row| normalize_message_row(row) }
    end

    # PSID profile for Messenger customers (distinct from OAuth /me fetch_user_profile).
    def fetch_messenger_user_profile(user_id:, page_access_token:)
      response = HTTParty.get(
        "#{graph_base}/#{user_id}",
        query: {
          fields: 'id,name,profile_pic',
          access_token: page_access_token
        },
        timeout: HTTP_TIMEOUT
      )
      return nil if response.code.to_i == 404

      unless response.success?
        Rails.logger.warn(
          "[PatraGraphService#fetch_messenger_user_profile] user=#{user_id} http=#{response.code} body=#{response.body.to_s[0, 200]}"
        )
        return nil
      end

      data = response.parsed_response || {}
      profile_pic = data['profile_pic']
      profile_pic_url =
        if profile_pic.is_a?(Hash)
          profile_pic.dig('data', 'url') || profile_pic['url']
        else
          profile_pic
        end

      {
        id: data['id'].to_s,
        name: data['name'].to_s,
        profile_pic: profile_pic_url.to_s
      }
    rescue StandardError => e
      Rails.logger.warn("[PatraGraphService#fetch_messenger_user_profile] #{e.class}: #{e.message.to_s[0, 200]}")
      nil
    end

    private

    def graph_base
      "#{GRAPH_HOST}/#{GRAPH_VERSION}"
    end

    def resolve_app_credentials(app_id, app_secret)
      resolved_id = app_id.presence || fb_app_id
      resolved_secret = app_secret.presence || fb_app_secret
      raise ArgumentError, 'FB_APP_ID is not configured' if resolved_id.blank?
      raise ArgumentError, 'FB_APP_SECRET is not configured' if resolved_secret.blank?

      [resolved_id, resolved_secret]
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

    def normalize_conversation_row(row)
      participants = Array(row.dig('participants', 'data')).map do |p|
        { id: p['id'].to_s, name: p['name'].to_s }
      end
      {
        id: row['id'].to_s,
        updated_time: row['updated_time'],
        participants: participants
      }
    end

    def normalize_message_row(row)
      from = row['from'].is_a?(Hash) ? row['from'] : {}
      {
        id: row['id'].to_s,
        created_time: row['created_time'],
        from_id: from['id'].to_s,
        from_name: from['name'].to_s,
        message: row['message'].to_s
      }
    end

    def fetch_paginated_graph_data(url:, query:, limit:, context:)
      items = []
      use_query = true
      next_url = url

      loop do
        response =
          if use_query
            HTTParty.get(next_url, query: query, timeout: HTTP_TIMEOUT)
          else
            HTTParty.get(next_url, timeout: HTTP_TIMEOUT)
          end
        raise_graph_error!(response, context) unless response.success?

        body = response.parsed_response
        Array(body['data']).each do |row|
          items << row
          return items if items.length >= limit
        end

        paging_next = body.dig('paging', 'next')
        break if paging_next.blank?

        next_url = paging_next
        use_query = false
      end

      items
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
