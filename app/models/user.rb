class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: JwtDenylist

  # UUID as primary key
  before_create :generate_uuid, :generate_jti

  # Validations
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, presence: true, length: { minimum: 8 }, on: :create
  validates :jti, presence: true, uniqueness: true

  # Additional safety: ensure jti before validation too
  before_validation :generate_jti

  private

  def generate_uuid
    self.id = SecureRandom.uuid unless self.id.present?
  end

  def generate_jti
    self.jti = SecureRandom.uuid if self.jti.blank?
  end
end
