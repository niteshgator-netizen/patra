class Api::V1::Accounts::BellaRagUploadsController < Api::V1::Accounts::BaseController
  def create
    file = params[:file]
    return render(json: { error: 'no file provided' }, status: :unprocessable_entity) unless file

    upload = Current.account.bella_rag_uploads.create!(
      user: Current.user,
      filename: file.original_filename.to_s[0, 255],
      file_size_bytes: file.size,
      raw_content: file.read
    )
    BellaRag::ProcessUploadJob.perform_later(upload.id)
    render json: { upload_id: upload.id, status: 'queued', filename: upload.filename }, status: :accepted
  end

  def index
    uploads = Current.account.bella_rag_uploads.recent.limit(50)
    render json: uploads.map { |u|
      {
        id: u.id,
        filename: u.filename,
        status: u.status,
        pairs_created: u.pairs_created,
        pairs_skipped: u.pairs_skipped,
        created_at: u.created_at,
        error_message: u.error_message
      }
    }
  end

  def stats
    total = Current.account.bella_rag_pairs.count
    labeled = Current.account.bella_rag_pairs.where.not(real_intent: nil).count
    awaiting_review = Current.account.bella_takeover_candidates
                             .where(status: 'queued').count rescue 0

    period = 7.days.ago.beginning_of_day..Time.current
    ai_handle_rate = begin
      Analytics::AiHandleRateService.new(Current.account, period: period).call[:rate]
    rescue StandardError
      0
    end

    render json: {
      total_pairs: total,
      labeled_pairs: labeled,
      label_progress_pct: total.zero? ? 0 : ((labeled.to_f / total) * 100).round(1),
      ai_handle_rate: ai_handle_rate,
      awaiting_review: awaiting_review
    }
  end
end
