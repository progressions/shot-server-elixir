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
        "https://chiwar.net",
        "https://shot-client-phoenix.fly.dev",
        "https://shot-client-next.fly.dev"
      ]
  end

  pipeline :authenticated do
    plug ShotElixirWeb.AuthPipeline
    plug Guardian.Plug.EnsureAuthenticated
  end

  # OAuth flow pipeline - supports token in query params for browser redirects
  pipeline :oauth_authenticated do
    plug ShotElixirWeb.AuthPipeline
    plug ShotElixirWeb.Plugs.VerifyTokenParam
  end

  # Health check endpoint
  scope "/", ShotElixirWeb do
    pipe_through :api
    get "/health", HealthController, :show
  end

  # Google OAuth endpoints (public - initiates OAuth flow)
  scope "/auth", ShotElixirWeb do
    pipe_through :api

    get "/google", GoogleOAuthController, :authorize
    get "/google/callback", GoogleOAuthController, :callback
  end

  # Notion OAuth endpoints (uses oauth_authenticated - supports token in query params)
  scope "/auth", ShotElixirWeb do
    pipe_through [:api, :oauth_authenticated]

    get "/notion/authorize", NotionOAuthController, :authorize
    get "/notion/callback", NotionOAuthController, :callback
  end

  # Authentication endpoints (Devise compatible)
  scope "/users", ShotElixirWeb.Users do
    pipe_through :api

    post "/sign_in", SessionsController, :create
    post "/sign_up", RegistrationsController, :create
    post "/", RegistrationsController, :create
    post "/confirmation", ConfirmationsController, :create
    get "/confirmation", ConfirmationsController, :create
    post "/password", PasswordsController, :create
    patch "/password", PasswordsController, :update

    # OTP Passwordless Login
    post "/otp/request", OtpController, :request
    post "/otp/verify", OtpController, :verify
    get "/otp/magic/:token", OtpController, :magic_link
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

    # WebAuthn/Passkey authentication (public endpoints)
    post "/webauthn/authenticate/options", WebauthnController, :authentication_options
    post "/webauthn/authenticate/verify", WebauthnController, :verify_authentication

    # Player View magic link redemption (public)
    post "/player_tokens/:token/redeem", PlayerViewTokenController, :redeem

    # Invitation show (public for redemption page)
    get "/invitations/:id", InvitationController, :show

    # Invitation registration (public - creates new user from invitation)
    post "/invitations/:id/register", InvitationController, :register

    # CLI device authorization (public endpoints)
    post "/cli/auth/start", CliAuthController, :start
    post "/cli/auth/poll", CliAuthController, :poll

    # Notion webhook (public - receives events from Notion)
    post "/webhooks/notion", NotionWebhookController, :webhook
  end

  # API V2 endpoints - Authenticated
  scope "/api/v2", ShotElixirWeb.Api.V2 do
    pipe_through [:api, :authenticated]

    # Backlinks
    get "/backlinks/:entity_type/:id", BacklinkController, :index

    # Search
    get "/search", SearchController, :index

    # Users
    get "/users/current", UserController, :current
    get "/users/profile", UserController, :profile
    get "/users/:id/profile", UserController, :profile
    patch "/users/profile", UserController, :update_profile
    post "/users/link_discord", UserController, :link_discord
    delete "/users/unlink_discord", UserController, :unlink_discord
    post "/users/change_password", UserController, :change_password
    delete "/users/:id/image", UserController, :remove_image
    resources "/users", UserController, except: [:create]

    # Notifications
    get "/notifications/unread_count", NotificationController, :unread_count
    post "/notifications/dismiss_all", NotificationController, :dismiss_all
    resources "/notifications", NotificationController, except: [:new, :edit]

    # Campaigns
    resources "/campaigns", CampaignController do
      patch "/set", CampaignController, :set
      get "/current_fight", CampaignController, :current_fight
      post "/members", CampaignController, :add_member
      delete "/members/:user_id", CampaignController, :remove_member
      post "/generate_batch_images", CampaignController, :generate_batch_images
      post "/reset_ai_credits", CampaignController, :reset_ai_credits
    end

    post "/campaigns/current", CampaignController, :set_current

    # Notion integration
    get "/notion/databases", NotionController, :databases
    get "/notion/search", NotionController, :search
    get "/notion/characters", NotionController, :search
    get "/notion/sites", NotionController, :search_sites
    get "/notion/parties", NotionController, :search_parties
    get "/notion/factions", NotionController, :search_factions
    get "/notion/junctures", NotionController, :search_junctures
    get "/notion/sessions", NotionController, :sessions
    get "/notion/adventures", NotionController, :adventures

    # Suggestions for @ mentions in rich text editors
    get "/suggestions", SuggestionsController, :index

    # Characters
    get "/characters/names", CharacterController, :autocomplete
    post "/characters/pdf", CharacterController, :import
    post "/characters/from_notion", CharacterController, :create_from_notion

    resources "/characters", CharacterController do
      post "/sync", CharacterController, :sync
      post "/sync_from_notion", CharacterController, :sync_from_notion
      post "/duplicate", CharacterController, :duplicate
      get "/pdf", CharacterController, :pdf
      delete "/image", CharacterController, :remove_image
      post "/notion/create", CharacterController, :create_notion_page
      get "/notion_page", CharacterController, :notion_page
      resources "/advancements", AdvancementController
      resources "/weapons", CharacterWeaponController, only: [:index, :create, :delete]
      resources "/schticks", CharacterSchtickController, only: [:index, :create, :delete]
      resources "/notion_sync_logs", NotionSyncLogController, only: [:index]
      delete "/notion_sync_logs/prune", NotionSyncLogController, :prune
    end

    # Vehicles
    get "/vehicles/archetypes", VehicleController, :archetypes

    resources "/vehicles", VehicleController do
      post "/duplicate", VehicleController, :duplicate
      delete "/image", VehicleController, :remove_image
      patch "/chase_state", VehicleController, :update_chase_state
    end

    # Fights
    resources "/fights", FightController do
      patch "/touch", FightController, :touch
      patch "/end_fight", FightController, :end_fight
      patch "/reset", FightController, :reset
      post "/add_party", FightController, :add_party
      delete "/image", FightController, :remove_image

      resources "/shots", ShotController, only: [:update, :delete] do
        post "/assign_driver", ShotController, :assign_driver
        delete "/remove_driver", ShotController, :remove_driver
      end

      resources "/character_effects", CharacterEffectController,
        only: [:index, :create, :update, :delete]

      # Fight events - combat action log
      resources "/fight_events", FightEventController, only: [:index]

      # Solo play endpoints
      post "/solo/start", SoloController, :start
      post "/solo/stop", SoloController, :stop
      get "/solo/status", SoloController, :status
      post "/solo/advance", SoloController, :advance
      post "/solo/action", SoloController, :player_action
      post "/solo/roll_initiative", SoloController, :roll_initiative

      # Locations for fights
      get "/locations", LocationController, :index_for_fight
      post "/locations", LocationController, :create_for_fight
    end

    # Standalone location routes (for update/delete without parent context)
    resources "/locations", LocationController, only: [:show, :update, :delete]

    # Quick-set location for shots (any campaign member can use)
    post "/shots/:id/set_location", ShotController, :set_location

    # Weapons with custom routes
    post "/weapons/batch", WeaponController, :batch
    get "/weapons/junctures", WeaponController, :junctures
    get "/weapons/categories", WeaponController, :categories

    resources "/weapons", WeaponController do
      post "/duplicate", WeaponController, :duplicate
      delete "/image", WeaponController, :remove_image
    end

    # Schticks with custom routes
    post "/schticks/batch", SchticksController, :batch
    get "/schticks/categories", SchticksController, :categories
    get "/schticks/paths", SchticksController, :paths
    post "/schticks/import", SchticksController, :import

    resources "/schticks", SchticksController do
      post "/duplicate", SchticksController, :duplicate
      delete "/image", SchticksController, :remove_image
    end

    resources "/junctures", JunctureController do
      delete "/image", JunctureController, :remove_image
      post "/sync", JunctureController, :sync
      post "/sync_from_notion", JunctureController, :sync_from_notion
      get "/notion_page", JunctureController, :notion_page
      resources "/notion_sync_logs", NotionSyncLogController, only: [:index]
      delete "/notion_sync_logs/prune", NotionSyncLogController, :prune
    end

    # Dice rolling
    post "/dice/swerve", DiceController, :swerve
    post "/dice/roll", DiceController, :roll
    post "/dice/exploding", DiceController, :exploding

    # Sites with attunement
    resources "/sites", SiteController do
      post "/duplicate", SiteController, :duplicate
      post "/attune", SiteController, :attune
      delete "/attune/:character_id", SiteController, :unattune
      delete "/image", SiteController, :remove_image
      post "/sync", SiteController, :sync
      post "/sync_from_notion", SiteController, :sync_from_notion
      get "/notion_page", SiteController, :notion_page
      resources "/notion_sync_logs", NotionSyncLogController, only: [:index]
      delete "/notion_sync_logs/prune", NotionSyncLogController, :prune

      # Locations for sites (templates)
      get "/locations", LocationController, :index_for_site
      post "/locations", LocationController, :create_for_site
    end

    # Parties with membership
    # Party templates (collection route - must be before resources)
    get "/parties/templates", PartyController, :list_templates

    resources "/parties", PartyController do
      post "/duplicate", PartyController, :duplicate
      post "/members", PartyController, :add_member
      delete "/members/:membership_id", PartyController, :remove_member
      delete "/image", PartyController, :remove_image
      post "/sync", PartyController, :sync
      post "/sync_from_notion", PartyController, :sync_from_notion
      get "/notion_page", PartyController, :notion_page
      resources "/notion_sync_logs", NotionSyncLogController, only: [:index]
      delete "/notion_sync_logs/prune", NotionSyncLogController, :prune

      # Party composition / slot management
      post "/apply_template", PartyController, :apply_template
      post "/slots", PartyController, :add_slot
      patch "/slots/:slot_id", PartyController, :update_slot
      delete "/slots/:slot_id", PartyController, :remove_slot
      post "/reorder_slots", PartyController, :reorder_slots
    end

    # Adventures
    resources "/adventures", AdventureController do
      post "/duplicate", AdventureController, :duplicate
      delete "/image", AdventureController, :remove_image
      post "/characters", AdventureController, :add_character
      delete "/characters/:character_id", AdventureController, :remove_character
      post "/villains", AdventureController, :add_villain
      delete "/villains/:character_id", AdventureController, :remove_villain
      post "/fights", AdventureController, :add_fight
      delete "/fights/:fight_id", AdventureController, :remove_fight
      post "/sync", AdventureController, :sync
      post "/sync_from_notion", AdventureController, :sync_from_notion
      get "/notion_page", AdventureController, :notion_page
      resources "/notion_sync_logs", NotionSyncLogController, only: [:index]
      delete "/notion_sync_logs/prune", NotionSyncLogController, :prune
    end

    resources "/factions", FactionController do
      post "/duplicate", FactionController, :duplicate
      delete "/image", FactionController, :remove_image
      post "/sync", FactionController, :sync
      post "/sync_from_notion", FactionController, :sync_from_notion
      get "/notion_page", FactionController, :notion_page
      resources "/notion_sync_logs", NotionSyncLogController, only: [:index]
      delete "/notion_sync_logs/prune", NotionSyncLogController, :prune
    end

    resources "/invitations", InvitationController, except: [:show] do
      post "/resend", InvitationController, :resend
    end

    post "/invitations/:id/redeem", InvitationController, :redeem

    # Encounters
    resources "/encounters", EncounterController, only: [:show] do
      patch "/act", EncounterController, :act
      post "/apply_combat_action", EncounterController, :apply_combat_action
      post "/apply_chase_action", EncounterController, :apply_chase_action
      patch "/update_initiatives", EncounterController, :update_initiatives

      # Player View magic link generation (GM only)
      get "/player_tokens", PlayerViewTokenController, :index
      post "/player_tokens", PlayerViewTokenController, :create
    end

    # AI Credentials
    resources "/ai_credentials", AiCredentialController, except: [:new, :edit, :show]

    # AI
    post "/ai", AiController, :create
    post "/ai/:id/extend", AiController, :extend

    post "/ai_images", AiImageController, :create
    post "/ai_images/attach", AiImageController, :attach

    # Media Library
    # Note: Explicit routes must come BEFORE resources to avoid matching as :id
    get "/media_library/search", MediaLibraryController, :search
    get "/media_library/ai_tags", MediaLibraryController, :ai_tags
    post "/media_library/bulk_delete", MediaLibraryController, :bulk_delete
    resources "/media_library", MediaLibraryController, only: [:index, :show, :delete]
    post "/media_library/:id/duplicate", MediaLibraryController, :duplicate
    post "/media_library/:id/attach", MediaLibraryController, :attach
    get "/media_library/:id/download", MediaLibraryController, :download

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

    # CLI device authorization (authenticated - approval and session management)
    post "/cli/auth/approve", CliAuthController, :approve
    get "/cli/sessions", CliAuthController, :list_sessions

    # WebAuthn/Passkey management (authenticated endpoints)
    post "/webauthn/register/options", WebauthnController, :registration_options
    post "/webauthn/register/verify", WebauthnController, :verify_registration
    get "/webauthn/credentials", WebauthnController, :list_credentials
    delete "/webauthn/credentials/:id", WebauthnController, :delete_credential
    patch "/webauthn/credentials/:id", WebauthnController, :update_credential
  end

  # Email preview in development
  if Mix.env() == :dev do
    scope "/dev" do
      pipe_through :browser
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  pipeline :admins_only do
    plug :admin_basic_auth
  end

  scope "/admin" do
    pipe_through [:browser, :admins_only]

    import Phoenix.LiveDashboard.Router
    import Oban.Web.Router

    oban_dashboard("/oban")
    live_dashboard "/dashboard", metrics: ShotElixirWeb.Telemetry
  end

  defp admin_basic_auth(conn, _opts) do
    {username, password} =
      if Application.get_env(:shot_elixir, :environment) == :prod do
        {
          System.fetch_env!("DASHBOARD_USER"),
          System.fetch_env!("DASHBOARD_PASS")
        }
      else
        {
          System.get_env("DASHBOARD_USER") || "admin",
          System.get_env("DASHBOARD_PASS") || "admin"
        }
      end

    Plug.BasicAuth.basic_auth(conn, username: username, password: password)
  end

  # WebSocket support
  # socket "/socket", ShotElixirWeb.UserSocket
end
