# frozen_string_literal: true

# Maps Zernio participant metadata (webhook conversation block or inbox API
# conversation list) onto Patra Contact fields. Also backfills contacts that
# were created with a raw PSID as the display name when a real name arrives
# on a later webhook.
module Messaging
  class ZernioContactEnrichment
    class << self
      def contact_attributes_from_inbound(parsed)
        build_contact_attributes(
          sender_id: parsed[:sender_id],
          sender_name: parsed[:sender_name],
          participant_name: parsed[:participant_name],
          participant_picture: parsed[:participant_picture],
          profile_url: parsed[:profile_url],
          platform: parsed[:platform]
        )
      end

      def contact_attributes_from_conversation(conv)
        conv_h = conv.respond_to?(:with_indifferent_access) ? conv.with_indifferent_access : conv
        build_contact_attributes(
          sender_id: conv_h['participantId'],
          sender_name: conv_h['participantName'],
          participant_name: conv_h['participantName'],
          participant_picture: conv_h['participantPicture'],
          profile_url: conv_h['url'],
          platform: conv_h['platform']
        )
      end

      def enrich_contact!(contact, parsed)
        return if contact.blank?

        attrs = contact_attributes_from_inbound(parsed)
        apply_enrichment!(contact, attrs)
      end

      def enrich_contact_from_conversation!(contact, conv)
        return if contact.blank?

        attrs = contact_attributes_from_conversation(conv)
        apply_enrichment!(contact, attrs)
      end

      private

      def build_contact_attributes(sender_id:, sender_name:, participant_name:, participant_picture:, profile_url:, platform:)
        psid = sender_id.to_s.presence
        display_name = resolve_display_name(
          sender_id: psid,
          sender_name: sender_name,
          participant_name: participant_name
        )

        additional = {
          zernio_sender_id: psid,
          zernio_platform: platform.to_s.presence
        }.compact

        picture = participant_picture.to_s.presence
        additional[:profile_picture] = picture if picture.present?

        url = usable_profile_url(profile_url, psid)
        additional[:profile_url] = url if url.present?

        {
          name: display_name,
          identifier: psid,
          avatar_url: picture,
          additional_attributes: additional
        }
      end

      def apply_enrichment!(contact, attrs)
        updates = {}

        new_name = attrs[:name].to_s.presence
        if new_name.present? && should_update_name?(contact.name, new_name, contact.identifier)
          updates[:name] = new_name
        end

        merged_additional = contact.additional_attributes.to_h.merge(attrs[:additional_attributes].to_h)
        updates[:additional_attributes] = merged_additional if merged_additional != contact.additional_attributes.to_h

        contact.update!(updates) if updates.present?

        avatar_url = attrs[:avatar_url].to_s.presence
        if avatar_url.present? && !contact.avatar.attached?
          ::Avatar::AvatarFromUrlJob.perform_later(contact, avatar_url)
        end
      rescue StandardError => e
        Rails.logger.warn(
          "[ZernioContactEnrichment] enrich failed contact=#{contact&.id} #{e.class}: #{e.message}"
        )
      end

      def resolve_display_name(sender_id:, sender_name:, participant_name:)
        psid = sender_id.to_s
        candidates = [sender_name, participant_name].map { |v| v.to_s.strip }.reject(&:blank?)

        candidates.each do |candidate|
          next if numeric_psid?(candidate)
          next if candidate == psid

          return candidate
        end

        suffix = psid.last(4).presence || '????'
        "Zernio User #{suffix}"
      end

      def should_update_name?(current_name, new_name, identifier)
        current = current_name.to_s.strip
        return true if current.blank?
        return true if numeric_psid?(current)
        return true if current == identifier.to_s
        return true if current.start_with?('Zernio User ')

        false
      end

      def numeric_psid?(value)
        value.to_s.match?(/\A\d{5,}\z/)
      end

      def usable_profile_url(url, psid)
        normalized = url.to_s.strip
        return nil if normalized.blank?
        return nil if psid_profile_url?(normalized, psid)

        normalized
      end

      def psid_profile_url?(url, psid)
        return true if url.match?(%r{\Ahttps?://(www\.)?facebook\.com/\d{5,}/?\z}i)
        return true if psid.present? && url.match?(%r{\Ahttps?://(www\.)?facebook\.com/#{Regexp.escape(psid)}/?\z}i)

        false
      end
    end
  end
end
