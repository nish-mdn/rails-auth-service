require 'jwt'

class JwtService
  # Paths to RSA keys
  PRIVATE_KEY_PATH = Rails.root.join('keys', 'private.pem')
  PUBLIC_KEY_PATH = Rails.root.join('keys', 'public.pem')

  # Algorithm for token encoding/decoding
  ALGORITHM = 'RS256'

  # Load the private key for signing tokens
  def self.private_key
    @private_key ||= OpenSSL::PKey::RSA.new(File.read(PRIVATE_KEY_PATH))
  end

  # Load the public key for verifying tokens
  def self.public_key
    @public_key ||= OpenSSL::PKey::RSA.new(File.read(PUBLIC_KEY_PATH))
  end

  # Encode (sign) a JWT token
  def self.encode(payload, exp = 24.hours.from_now)
    payload[:exp] = exp.to_i
    JWT.encode(payload, private_key, ALGORITHM)
  end

  # Decode and verify a JWT token
  def self.decode(token)
    JWT.decode(token, public_key, true, { algorithm: ALGORITHM })
  rescue JWT::DecodeError => e
    raise "Invalid token: #{e.message}"
  end

  # Generate RSA key pair (should be run once)
  def self.generate_keys
    rsa_key = OpenSSL::PKey::RSA.new(2048)
    
    # Write private key
    File.write(PRIVATE_KEY_PATH, rsa_key.to_pem)
    File.chmod(0600, PRIVATE_KEY_PATH)
    
    # Write public key
    File.write(PUBLIC_KEY_PATH, rsa_key.public_key.to_pem)
    
    puts "RSA keys generated successfully!"
    puts "Private key: #{PRIVATE_KEY_PATH}"
    puts "Public key: #{PUBLIC_KEY_PATH}"
  end

  # Return the public key for external services
  def self.public_key_pem
    File.read(PUBLIC_KEY_PATH)
  end
end
