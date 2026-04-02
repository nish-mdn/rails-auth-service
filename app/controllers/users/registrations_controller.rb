module Users
  class RegistrationsController < Devise::RegistrationsController
    skip_before_action :verify_authenticity_token, only: [:create]
    respond_to :html, :json

    # POST /users/sign_up
    def create
      build_resource(sign_up_params)

      # Ensure JTI is set before save
      resource.jti = SecureRandom.uuid if resource.jti.blank?

      if resource.save
        token = JwtService.encode({ user_id: resource.id, jti: resource.jti })
        
        render json: {
          status: :created,
          message: 'Account created successfully',
          token: token,
          user: user_json(resource)
        }, status: :created
      else
        # Collect all validation errors
        errors = resource.errors.full_messages
        
        # Log errors for debugging (optional)
        Rails.logger.warn("User registration failed: #{errors.inspect}")
        
        render json: {
          status: :unprocessable_entity,
          errors: errors,
          message: errors.first
        }, status: :unprocessable_entity
      end
    end

    private

    def sign_up_params
      params.require(:user).permit(:email, :password, :password_confirmation)
    end

    def user_json(user)
      {
        id: user.id,
        email: user.email,
        created_at: user.created_at,
        updated_at: user.updated_at
      }
    end
  end
end
