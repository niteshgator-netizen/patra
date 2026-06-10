# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public legal pages' do
  it 'serves /terms without authentication' do
    get '/terms'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('Terms of Service')
    expect(response.body).to include('Patra')
  end

  it 'serves /privacy without authentication' do
    get '/privacy'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('Privacy Policy')
    expect(response.body).to include('Data Deletion Request')
  end

  it 'routes both paths to LegalController' do
    expect(get: '/terms').to route_to(controller: 'legal', action: 'terms')
    expect(get: '/privacy').to route_to(controller: 'legal', action: 'privacy')
  end
end
