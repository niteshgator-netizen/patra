# frozen_string_literal: true

class Api::V1::Accounts::Patra::ClickToChatController < Api::V1::Accounts::BaseController
  def create
    link = ClickToChat::LinkGenerator.generate(
      account: Current.account,
      channel: params[:channel],
      utm_source: params[:utm_source],
      utm_campaign: params[:utm_campaign]
    )
    render json: { link: link }
  end
end
