class Api::V1::Accounts::Contacts::PresencesController < Api::V1::Accounts::BaseController
  before_action :contact

  def show
    authorize @contact, :show?
    render json: Facebook::ContactLastActive.presence_payload(@contact.id)
  end

  private

  def contact
    @contact = Current.account.contacts.find(params[:id])
  end
end
