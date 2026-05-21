# == Schema Information
#
# Table name: canned_responses
#
#  id         :integer          not null, primary key
#  content    :text
#  short_code :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :integer          not null
#

class CannedResponse < ApplicationRecord
  validates :content, presence: true
  validates :short_code, presence: true
  validates :account, presence: true
  validates :short_code, uniqueness: { scope: :account_id }

  belongs_to :account

  after_commit :sync_to_bella_rag, on: %i[create update]

  scope :order_by_search, lambda { |search|
    short_code_starts_with = sanitize_sql_array(['WHEN short_code ILIKE ? THEN 1', "#{search}%"])
    short_code_like = sanitize_sql_array(['WHEN short_code ILIKE ? THEN 0.5', "%#{search}%"])
    content_like = sanitize_sql_array(['WHEN content ILIKE ? THEN 0.2', "%#{search}%"])

    order_clause = "CASE #{short_code_starts_with} #{short_code_like} #{content_like} ELSE 0 END"

    order(Arel.sql(order_clause) => :desc)
  }

  private

  def sync_to_bella_rag
    return if short_code.blank? || content.blank?
    return unless account_id

    embed_input, embedding = embed_for_canned(short_code.to_s)
    pair = BellaRagPair.find_or_initialize_by(
      account_id: account_id,
      source: 'canned_response',
      customer_text: short_code.to_s
    )
    pair.assign_attributes(
      cashier_text: content.to_s,
      industry_slug: nil,
      approved: true,
      anonymized: false,
      embed_input: embed_input,
      embedding: embedding,
      embedding_model: Bella::VoyageEmbedder::MODEL
    )
    pair.save!
  rescue StandardError => e
    Rails.logger.warn("[CannedResponse##{id}#sync_to_bella_rag] #{e.class}: #{e.message[0, 200]}")
  end

  def embed_for_canned(text)
    input = "[customer]: #{text.to_s[0, 4000]}"
    vec = Bella::VoyageEmbedder.embed_one(input, input_type: 'document')
    raise Bella::VoyageEmbedder::EmbeddingError, 'empty embedding' if vec.blank?
    [input, vec]
  end
end
