# frozen_string_literal: true

class Api::V1::Accounts::Patra::ApiDocsController < Api::V1::Accounts::BaseController
  def index
    render json: ApiDocs::Generator.generate
  end
end
