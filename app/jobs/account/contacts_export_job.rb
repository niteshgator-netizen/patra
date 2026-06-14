class Account::ContactsExportJob < ApplicationJob
  queue_as :low

  LABELS_COLUMN = 'labels'.freeze
  LABELS_DELIMITER = ','.freeze
  # F2 — virtual (computed) columns allowed alongside real Contact columns.
  VIRTUAL_COLUMNS = %w[labels profile_link source_agent linked_inbox].freeze

  def perform(account_id, user_id, column_names, params)
    @account = Account.find(account_id)
    @params = params
    @account_user = @account.users.find(user_id)
    # F2 — the exporter's MEMBERSHIP (AccountUser, not the User) so we can apply their name-privacy tier.
    @exporter = @account.account_users.find_by(user_id: user_id)

    headers = valid_headers(column_names)
    generate_csv(headers)
    send_mail
  end

  private

  def generate_csv(headers)
    contacts_to_export = contacts.to_a
    preload_contact_labels(contacts_to_export) if headers.include?(LABELS_COLUMN)
    preload_source_agents(contacts_to_export) if headers.include?('source_agent')
    preload_linked_inboxes(contacts_to_export) if headers.include?('linked_inbox')

    csv_data = CSV.generate do |csv|
      csv << headers
      contacts_to_export.each do |contact|
        csv << headers.map { |header| value_for_header(contact, header) }
      end
    end

    attach_export_file(csv_data)
  end

  def value_for_header(contact, header)
    case header
    when LABELS_COLUMN
      contact_labels_by_id.fetch(contact.id, []).join(LABELS_DELIMITER)
    when 'name'
      # F2 — honor the EXPORTER's name-privacy tier (Phase C): owner/admin -> full; restricted -> masked.
      Patra::ContactPrivacy.display_name(contact, @exporter)
    when 'profile_link'
      contact_profile_link(contact)
    when 'source_agent'
      source_agent_by_id[contact.id].to_s
    when 'linked_inbox'
      linked_inbox_by_id.fetch(contact.id, []).uniq.join(LABELS_DELIMITER)
    else
      contact.send(header)
    end
  end

  def approved_labels
    @approved_labels ||= @account.labels.pluck(:title)
  end

  def preload_contact_labels(contacts_to_export)
    contact_ids = contacts_to_export.map(&:id)
    return if contact_ids.blank?

    ActsAsTaggableOn::Tagging
      .joins(:tag)
      .where(context: LABELS_COLUMN, taggable_type: 'Contact', taggable_id: contact_ids)
      .where(tags: { name: approved_labels })
      .pluck(:taggable_id, 'tags.name')
      .each { |contact_id, label| contact_labels_by_id[contact_id] << label }
  end

  def contact_labels_by_id
    @contact_labels_by_id ||= Hash.new { |hash, contact_id| hash[contact_id] = [] }
  end

  # F2 — cross-channel profile link from enrichment (FB/Zernio store it in additional_attributes).
  def contact_profile_link(contact)
    attrs = contact.additional_attributes || {}
    attrs['fb_profile_link'].presence ||
      attrs['profile_url'].presence ||
      attrs.dig('social_profiles', 'facebook').presence ||
      ''
  rescue StandardError
    ''
  end

  def source_agent_by_id
    @source_agent_by_id ||= {}
  end

  def linked_inbox_by_id
    @linked_inbox_by_id ||= Hash.new { |hash, contact_id| hash[contact_id] = [] }
  end

  # F2 — most-recent conversation assignee per contact (the "source agent"), in ONE query + one name
  # lookup. Avoids N+1 on large (73k-contact) accounts.
  def preload_source_agents(contacts_to_export)
    ids = contacts_to_export.map(&:id)
    return if ids.blank?

    contact_assignee = {}
    @account.conversations.where(contact_id: ids).where.not(assignee_id: nil)
            .order(:last_activity_at).pluck(:contact_id, :assignee_id)
            .each { |contact_id, assignee_id| contact_assignee[contact_id] = assignee_id } # last wins => most recent
    names = User.where(id: contact_assignee.values.uniq).pluck(:id, :name).to_h
    contact_assignee.each { |contact_id, assignee_id| source_agent_by_id[contact_id] = names[assignee_id] }
  end

  # F2 — the inbox(es)/linked account each contact is connected through, in ONE query.
  def preload_linked_inboxes(contacts_to_export)
    ids = contacts_to_export.map(&:id)
    return if ids.blank?

    ContactInbox.joins(:inbox).where(contact_id: ids)
                .pluck(:contact_id, 'inboxes.name')
                .each { |contact_id, name| linked_inbox_by_id[contact_id] << name if name.present? }
  end

  def contacts
    if @params.present? && @params[:payload].present? && @params[:payload].any?
      result = ::Contacts::FilterService.new(@account, @account_user, @params).perform
      result[:contacts]
    elsif @params[:label].present?
      @account.contacts.resolved_contacts(use_crm_v2: @account.feature_enabled?('crm_v2')).tagged_with(@params[:label], any: true)
    else
      @account.contacts.resolved_contacts(use_crm_v2: @account.feature_enabled?('crm_v2'))
    end
  end

  def valid_headers(column_names)
    requested_headers = column_names.presence || default_columns

    # Keep requested header order while allowing the virtual labels column.
    requested_headers.select do |header|
      VIRTUAL_COLUMNS.include?(header) || Contact.column_names.include?(header)
    end.uniq
  end

  def attach_export_file(csv_data)
    return if csv_data.blank?

    # Prepend UTF-8 BOM so that spreadsheet applications (e.g. Excel)
    # correctly recognise the file encoding for non-ASCII characters
    # such as Arabic, Japanese, and Chinese.
    bom = "\xEF\xBB\xBF"

    @account.contacts_export.attach(
      io: StringIO.new("#{bom}#{csv_data}"),
      filename: "#{@account.name}_#{@account.id}_contacts.csv",
      content_type: 'text/csv'
    )
  end

  def send_mail
    file_url = account_contact_export_url
    mailer = AdministratorNotifications::AccountNotificationMailer.with(account: @account)
    mailer.contact_export_complete(file_url, @account_user.email)&.deliver_later
  end

  def account_contact_export_url
    Rails.application.routes.url_helpers.rails_blob_url(@account.contacts_export)
  end

  def default_columns
    # F2 — name is now privacy-masked per exporter; profile_link added by default (cheap, from
    # additional_attributes). source_agent / linked_inbox stay OPT-IN (heavier preloads) — request
    # them explicitly for a full export so default exports of large (73k) accounts stay light.
    %w[id name profile_link email phone_number labels]
  end
end
