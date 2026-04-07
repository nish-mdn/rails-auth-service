Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions: 'users/sessions',
    registrations: 'users/registrations'
  }

  # API routes for public key access
  namespace :api do
    namespace :v1 do
      resources :public_keys, only: [:show]
    end
  end

  # Custom signup route for backward compatibility
  post 'users/sign_up', to: 'users/registrations#create'

  # Root path
  root 'pages#home'

  # Health check
  get 'health', to: 'pages#health'
  
  # Optional: Catch-all for development
  match '*path', to: 'pages#not_found', via: :all
end
