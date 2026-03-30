module Api
  module V1
    class PublicKeysController < ApplicationController
      skip_before_action :verify_authenticity_token

      # GET /api/v1/public_key
      # Returns the public RSA key for verifying JWTs
      def show
        render json: {
          public_key: JwtService.public_key_pem,
          algorithm: 'RS256'
        }, status: :ok
      end
    end
  end
end
