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
end
