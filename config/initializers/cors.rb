Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Allow requests from localhost with any port (development)
    origins 'localhost', '127.0.0.1'
    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options],
      credentials: true
  end

  allow do
    # Allow requests from the Main App (change this to actual domain in production)
    origins ENV.fetch('CORS_ALLOWED_ORIGINS', 'localhost:3000').split(',')
    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options],
      credentials: true,
      expose: ['Authorization', 'Content-Type']
  end
end
