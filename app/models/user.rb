class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: JwtDenylist

  # UUID as primary key
  before_create :generate_uuid

  # Validations
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, presence: true, length: { minimum: 8 }, on: :create
  validates :jti, presence: true, uniqueness: true

  # Callbacks
  before_save :ensure_jti

  private

  def generate_uuid
    self.id = SecureRandom.uuid unless self.id.present?
  end

  def ensure_jti
    self.jti ||= SecureRandom.uuid
  end
end
