defmodule ShotElixir.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialize ETS table for rate limiting
    ShotElixir.Invitations.init_rate_limiting()

    children = [
      ShotElixirWeb.Telemetry,
      ShotElixir.Repo,
      # Oban for background jobs (emails, etc.)
      {Oban, Application.fetch_env!(:shot_elixir, Oban)},
      {DNSCluster, query: Application.get_env(:shot_elixir, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ShotElixir.PubSub},
      # Phoenix Presence for tracking users in channels
      ShotElixirWeb.Presence,
      # Cachex for image URL caching
      {Cachex, name: :image_cache},
      # Finch HTTP client for Swoosh email delivery
      {Finch, name: Swoosh.Finch},
      # Discord bot consumer
      ShotElixir.Discord.Consumer,
      # Discord current fight Agent
      ShotElixir.Discord.CurrentFight,
      # Start a worker by calling: ShotElixir.Worker.start_link(arg)
      # {ShotElixir.Worker, arg},
      # Start to serve requests, typically the last entry
      ShotElixirWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ShotElixir.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ShotElixirWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
