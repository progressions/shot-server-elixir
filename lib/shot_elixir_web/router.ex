defmodule ShotElixirWeb.Router do
  use ShotElixirWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]

    plug CORSPlug,
      origin: [
        "http://localhost:3001",
        "http://localhost:3000",
        "https://shot-client-phoenix.fly.dev",
        "https://shot-client-next.fly.dev"
      ]
  end

  pipeline :authenticated do
    plug ShotElixirWeb.AuthPipeline
    plug Guardian.Plug.EnsureAuthenticated
  end

  # Health check endpoint
  scope "/", ShotElixirWeb do
    pipe_through :api
    get "/health", HealthController, :show
  end

  # Authentication endpoints (Devise compatible)
  scope "/users", ShotElixirWeb.Users do
    pipe_through :api

    post "/sign_in", SessionsController, :create
    post "/sign_up", RegistrationsController, :create
    post "/", RegistrationsController, :create
    post "/confirm", ConfirmationsController, :create
    post "/password", PasswordsController, :create
    put "/password", PasswordsController, :update
  end

  # Authenticated endpoints
  scope "/users", ShotElixirWeb.Users do
    pipe_through [:api, :authenticated]

    delete "/sign_out", SessionsController, :delete
  end

  # API V2 endpoints - Public (no auth required)
  scope "/api/v2", ShotElixirWeb.Api.V2 do
    pipe_through :api

    # User registration (public)
    post "/users", UserController, :create
    post "/users/register", UserController, :register
  end

  # API V2 endpoints - Authenticated
  scope "/api/v2", ShotElixirWeb.Api.V2 do
    pipe_through [:api, :authenticated]

    # Users
    get "/users/current", UserController, :current
    get "/users/profile", UserController, :profile
    get "/users/:id/profile", UserController, :profile
    patch "/users/profile", UserController, :update_profile
    delete "/users/:id/image", UserController, :remove_image
    resources "/users", UserController, except: [:create]

    # Campaigns
    resources "/campaigns", CampaignController do
      patch "/set", CampaignController, :set
      get "/current_fight", CampaignController, :current_fight
      post "/members", CampaignController, :add_member
      delete "/members/:user_id", CampaignController, :remove_member
    end

    post "/campaigns/current", CampaignController, :set_current

    # Characters
    get "/characters/names", CharacterController, :autocomplete
    post "/characters/pdf", CharacterController, :import

    resources "/characters", CharacterController do
      post "/sync", CharacterController, :sync
      post "/duplicate", CharacterController, :duplicate
      get "/pdf", CharacterController, :pdf
      resources "/advancements", AdvancementController
    end

    # Vehicles
    get "/vehicles/archetypes", VehicleController, :archetypes

    resources "/vehicles", VehicleController do
      delete "/image", VehicleController, :remove_image
      patch "/chase_state", VehicleController, :update_chase_state
    end

    # Fights
    resources "/fights", FightController do
      patch "/touch", FightController, :touch
      patch "/end_fight", FightController, :end_fight
      delete "/image", FightController, :remove_image

      resources "/shots", ShotController, only: [:update, :delete] do
        post "/assign_driver", ShotController, :assign_driver
        delete "/remove_driver", ShotController, :remove_driver
      end
    end

    # Weapons with custom routes
    post "/weapons/batch", WeaponController, :batch
    get "/weapons/junctures", WeaponController, :junctures
    get "/weapons/categories", WeaponController, :categories

    resources "/weapons", WeaponController do
      delete "/image", WeaponController, :remove_image
    end

    # Schticks with custom routes
    post "/schticks/batch", SchticksController, :batch
    get "/schticks/categories", SchticksController, :categories
    get "/schticks/paths", SchticksController, :paths
    post "/schticks/import", SchticksController, :import

    resources "/schticks", SchticksController do
      delete "/image", SchticksController, :remove_image
    end

    resources "/junctures", JunctureController do
      delete "/image", JunctureController, :remove_image
    end

    # Sites with attunement
    resources "/sites", SiteController do
      post "/attune", SiteController, :attune
      delete "/attune/:character_id", SiteController, :unattune
      delete "/image", SiteController, :remove_image
    end

    # Parties with membership
    resources "/parties", PartyController do
      post "/members", PartyController, :add_member
      delete "/members/:membership_id", PartyController, :remove_member
      delete "/image", PartyController, :remove_image
    end

    resources "/factions", FactionController do
      delete "/image", FactionController, :remove_image
    end

    resources "/invitations", InvitationController

    # Encounters
    resources "/encounters", EncounterController, only: [:show] do
      patch "/act", EncounterController, :act
      post "/apply_combat_action", EncounterController, :apply_combat_action
      post "/apply_chase_action", EncounterController, :apply_chase_action
      patch "/update_initiatives", EncounterController, :update_initiatives
    end

    # AI
    resources "/ai", AiController, only: [:create] do
      patch "/extend", AiController, :extend
    end

    post "/ai_images", AiImageController, :create
    post "/ai_images/attach", AiImageController, :attach

    resources "/chase_relationships", ChaseRelationshipController, except: [:new, :edit]

    get "/image_positions/:positionable_type/:positionable_id", ImagePositionController, :show
    patch "/image_positions/:positionable_type/:positionable_id", ImagePositionController, :update
    put "/image_positions/:positionable_type/:positionable_id", ImagePositionController, :update
    resources "/image_positions", ImagePositionController, only: [:create]

    # Onboarding
    scope "/onboarding" do
      patch "/dismiss_congratulations", OnboardingController, :dismiss_congratulations
      patch "/", OnboardingController, :update
    end
  end

  # Email preview in development
  if Mix.env() == :dev do
    scope "/dev" do
      pipe_through :browser
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # WebSocket support
  # socket "/socket", ShotElixirWeb.UserSocket
end
