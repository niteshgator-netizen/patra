# frozen_string_literal: true

module Backup
  # Patra (B-INVITE) — composes the connect-up message listing the LIVE backups' m.me links.
  # The owner can override the wording via account.custom_attributes['backup_invite_message']; the
  # literal token %{links} (if present) is replaced with the page links, otherwise links are
  # appended. Returns nil when there are no live backups to invite to (caller must not send).
  class InviteComposer
    DEFAULT_TEMPLATE = "Quick favor so we never lose touch — tap each link and send a quick 'hi' " \
                       'so we stay connected on all our pages: %{links}'
    PLACEHOLDER = '%{links}'

    def initialize(account)
      @account = account
    end

    def links
      @account.backup_pages.live_backups.ordered.map(&:m_me_link)
    end

    def message
      page_links = links
      return nil if page_links.empty?

      joined = page_links.join('  ')
      template.include?(PLACEHOLDER) ? template.gsub(PLACEHOLDER, joined) : "#{template} #{joined}"
    end

    private

    def template
      raw = @account.custom_attributes&.dig('backup_invite_message')
      raw.presence || DEFAULT_TEMPLATE
    end
  end
end
