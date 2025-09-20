defmodule ShotElixir.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ShotElixirWeb.Telemetry,
      ShotElixir.Repo,
      {DNSCluster, query: Application.get_env(:shot_elixir, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ShotElixir.PubSub},
      # Phoenix Presence for tracking users in channels
      ShotElixirWeb.Presence,
      # Cachex for image URL caching
      {Cachex, name: :image_cache},
      # Redis connection for presence tracking
      {Redix, name: :redix, host: "localhost", port: 6379},
      # BroadcastManager for Rails-compatible WebSocket broadcasting
      ShotElixir.BroadcastManager,
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
