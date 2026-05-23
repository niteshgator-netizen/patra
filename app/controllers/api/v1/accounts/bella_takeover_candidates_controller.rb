class Api::V1::Accounts::BellaTakeoverCandidatesController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :load_candidate, only: [:update]

  def index
    scope = Current.account.bella_takeover_candidates.order(created_at: :desc)
    scope = scope.where(status: params[:status]) if params[:status].present?
    render json: scope.limit(100).map { |c| serialize(c) }
  end

  def update
    new_status = candidate_params[:status].to_s
    unless BellaTakeoverCandidate::STATUSES.include?(new_status)
      return render json: { error: 'invalid status' }, status: :unprocessable_entity
    end

    @candidate.update!(status: new_status)
    BellaRag::IngestCandidateJob.perform_later(@candidate.id) if new_status == 'approved'
    render json: serialize(@candidate)
  rescue StandardError => e
    Rails.logger.error("[BellaTakeoverCandidates] update failed id=#{params[:id]} #{e.class}: #{e.message}")
    render json: { error: 'update failed' }, status: :unprocessable_entity
  end

  private

  def load_candidate
    @candidate = Current.account.bella_takeover_candidates.find(params[:id])
  end

  def candidate_params
    params.require(:bella_takeover_candidate).permit(:status)
  end

  def serialize(candidate)
    {
      id: candidate.id,
      conversation_id: candidate.conversation_id,
      message_id: candidate.message_id,
      customer_text: candidate.customer_text,
      human_reply: candidate.human_reply,
      confidence_score: candidate.confidence_score,
      status: candidate.status,
      resulting_pair_id: candidate.resulting_pair_id,
      created_at: candidate.created_at
    }
  end
end
