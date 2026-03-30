class ApplicationController < ActionController::Base
  include Devise::Controllers::Helpers

  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :set_default_format

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:email, :password, :password_confirmation])
    devise_parameter_sanitizer.permit(:sign_in, keys: [:email, :password])
  end

  private

  def set_default_format
    request.format = :json if request.xhr? || request.path.start_with?('/api')
  end
end
