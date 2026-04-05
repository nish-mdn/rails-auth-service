# app/services/s3_service.rb
#
# Service for all S3 operations used by rails-auth-service.
# Credentials are supplied transparently by IRSA (no hardcoded keys).
#
# Usage:
#   s3 = S3Service.new
#   s3.upload(key: "uploads/avatar.png", file: File.open("/path/to/file"))
#   s3.download(key: "uploads/avatar.png")   # => String (binary content)
#   s3.list(prefix: "uploads/")              # => Array of hashes
#   s3.delete(key: "uploads/avatar.png")
#   s3.presigned_url(key: "uploads/avatar.png", expires_in: 3600)

class S3Service
  def initialize
    @bucket = ENV.fetch("S3_BUCKET_NAME")
    @client = Aws::S3::Client.new
  end

  # Upload a file or IO object to the bucket.
  # @param key [String]  the S3 object key (e.g. "uploads/user-1/photo.jpg")
  # @param file [IO, String]  file handle or raw string body
  # @param content_type [String, nil]
  # @return [String] the object key
  def upload(key:, file:, content_type: nil)
    options = { bucket: @bucket, key: key, body: file }
    options[:content_type] = content_type if content_type
    @client.put_object(options)
    key
  end

  # Download and return the raw body of an object.
  # @param key [String]
  # @return [String] binary content
  def download(key:)
    @client.get_object(bucket: @bucket, key: key).body.read
  end

  # List objects under an optional prefix.
  # @param prefix [String, nil]
  # @return [Array<Hash>] each entry has :key, :size, :last_modified
  def list(prefix: nil)
    options = { bucket: @bucket }
    options[:prefix] = prefix if prefix
    @client.list_objects_v2(options).contents.map do |obj|
      { key: obj.key, size: obj.size, last_modified: obj.last_modified }
    end
  end

  # Delete a single object.
  # @param key [String]
  def delete(key:)
    @client.delete_object(bucket: @bucket, key: key)
  end

  # Generate a pre-signed URL for temporary direct access.
  # @param key [String]
  # @param expires_in [Integer] seconds until URL expires (default 1 h)
  # @param method [Symbol] :get or :put
  # @return [String] pre-signed URL
  def presigned_url(key:, expires_in: 3600, method: :get)
    Aws::S3::Presigner.new(client: @client)
      .presigned_url("#{method}_object", bucket: @bucket, key: key, expires_in: expires_in)
  end
end
