defmodule ShotElixirWeb.Router do
  use ShotElixirWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug CORSPlug, origin: ["http://localhost:3001", "http://localhost:3000"]
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
  end

  # API V2 endpoints - Authenticated
  scope "/api/v2", ShotElixirWeb.Api.V2 do
    pipe_through [:api, :authenticated]

    # Users
    get "/users/current", UserController, :current
    get "/users/profile", UserController, :profile
    get "/users/:id/profile", UserController, :profile
    patch "/users/profile", UserController, :update_profile
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
    end

    # Vehicles
    resources "/vehicles", VehicleController
    get "/vehicles/archetypes", VehicleController, :archetypes

    # Fights
    resources "/fights", FightController do
      patch "/touch", FightController, :touch
      patch "/end_fight", FightController, :end_fight

      resources "/shots", ShotController, only: [:update, :delete] do
        post "/assign_driver", ShotController, :assign_driver
        delete "/remove_driver", ShotController, :remove_driver
      end
    end

    # Other resources
    resources "/weapons", WeaponController
    resources "/schticks", SchticksController
    resources "/junctures", JunctureController
    resources "/sites", SiteController
    resources "/parties", PartyController
    resources "/factions", FactionController
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

    resources "/ai_images", AiImageController, only: [:create] do
      post "/attach", AiImageController, :attach
    end

    # Onboarding
    scope "/onboarding" do
      patch "/dismiss_congratulations", OnboardingController, :dismiss_congratulations
      patch "/", OnboardingController, :update
    end
  end

  # WebSocket support
  # socket "/socket", ShotElixirWeb.UserSocket
end
