# frozen_string_literal: true

# patra-final 5e (G44): cross-account player search for the operator console.
# READ-ONLY — no mutations, no member actions. Searches contacts by
# name/phone/email/platform identifier and by sweeps game username
# (GameAction.game_username), and shows per-player load/cashout totals.
class SuperAdmin::PatraPlayersController < SuperAdmin::ApplicationController
  RESULT_LIMIT = 50

  def show
    @query = params[:q].to_s.strip
    @contacts = []
    @totals = {}
    return if @query.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"

    contact_ids = Contact.where(
      'contacts.name ILIKE :p OR contacts.email ILIKE :p OR contacts.phone_number ILIKE :p OR contacts.identifier ILIKE :p',
      p: pattern
    ).limit(RESULT_LIMIT).pluck(:id)

    game_contact_ids = GameAction.where('game_username ILIKE ?', pattern)
                                 .where.not(contact_id: nil)
                                 .distinct.limit(RESULT_LIMIT).pluck(:contact_id)

    @contacts = Contact.where(id: (contact_ids + game_contact_ids).uniq.first(RESULT_LIMIT))
                       .includes(:account)
                       .order(:account_id, :id)

    @totals = load_totals(@contacts.map(&:id))
  end

  private

  # { contact_id => { 'load' => 123.0, 'cashout' => 45.0 } }
  def load_totals(contact_ids)
    return {} if contact_ids.empty?

    GameAction.where(contact_id: contact_ids, status: 'success', action_type: %w[load cashout])
              .group(:contact_id, :action_type)
              .sum(:amount)
              .each_with_object({}) do |((contact_id, action_type), sum), acc|
      (acc[contact_id] ||= {})[action_type] = sum
    end
  end
end
