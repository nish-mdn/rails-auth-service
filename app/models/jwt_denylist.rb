class JwtDenylist < ApplicationRecord
  include Devise::JWT::RevocationStrategies::Denylist

  # This table stores revoked JTIs (JWT IDs) for instant token revocation
  # Foreign key: jti (the JWT identifier)
  validates :jti, presence: true, uniqueness: true
end
