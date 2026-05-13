# == Schema Information
#
# Table name: games
#
#  id                 :bigint           not null, primary key
#  name               :string           not null
#  slug               :string           not null
#  logo_emoji         :string
#  logo_url           :string
#  domain             :string
#  player_signup_url  :string
#  agent_login_url    :string
#  api_base_url       :string
#  has_api            :boolean          default(FALSE), not null
#  api_docs_url       :string
#  auth_method        :string
#  required_fields    :jsonb            default([]), not null
#  description        :text
#  status             :string           default("active"), not null
#  sort_order         :integer          default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
class Game < ApplicationRecord
  STATUSES = %w[active deprecated].freeze
  AUTH_METHODS = %w[md5_token bearer api_key none].freeze

  has_many :agent_games, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
            format: { with: /\A[a-z0-9_]+\z/, message: "only allows lowercase letters, numbers, and underscores" }
  validates :status, inclusion: { in: STATUSES }
  validates :auth_method, inclusion: { in: AUTH_METHODS, allow_nil: true }

  scope :active, -> { where(status: 'active') }
  scope :with_api, -> { where(has_api: true) }
  scope :ordered, -> { order(sort_order: :asc, name: :asc) }

  def active?
    status == 'active'
  end

  def required_field_names
    return [] unless required_fields.is_a?(Array)
    required_fields.map { |f| f['name'] }.compact
  end
end
