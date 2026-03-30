class PagesController < ApplicationController
  skip_before_action :verify_authenticity_token

  def home
    render json: {
      message: 'Auth Service is running',
      version: '1.0.0'
    }
  end

  def health
    render json: { status: 'ok' }, status: :ok
  end

  def not_found
    render json: {
      error: 'Not Found',
      message: 'The requested resource could not be found'
    }, status: :not_found
  end
end
