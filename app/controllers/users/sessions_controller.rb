module Users
  class SessionsController < Devise::SessionsController
    skip_before_action :verify_authenticity_token, only: [:create, :destroy]
    before_action :authenticate_user!, only: [:destroy]

    respond_to :html, :json

    # POST /users/sign_in
    def create
      user = User.find_by(email: session_params[:email])

      if user&.valid_password?(session_params[:password])
        sign_in(user)
        token = JwtService.encode({ user_id: user.id, jti: user.jti })
        
        render json: {
          status: :ok,
          message: 'Logged in successfully from argocd deployments',
          token: token,
          user: user_json(user)
        }, status: :ok
      else
        render json: {
          status: :unprocessable_entity,
          message: 'Invalid email or password'
        }, status: :unprocessable_entity
      end
    end

    # DELETE /users/sign_out
    def destroy
      # Add JWT to denylist for instant revocation
      token = request.headers['Authorization'].to_s.gsub('Bearer ', '')
      
      if token.present?
        begin
          decoded = JwtService.decode(token)
          JwtDenylist.create!(jti: decoded[0]['jti'])
        rescue => e
          Rails.logger.warn("Error blacklisting token: #{e.message}")
        end
      end

      sign_out(current_user)
      render json: {
        status: :ok,
        message: 'Logged out successfully'
      }, status: :ok
    end

    private

    def session_params
      params.require(:user).permit(:email, :password)
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
