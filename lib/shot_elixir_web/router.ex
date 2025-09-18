defmodule ShotElixirWeb.Router do
  use ShotElixirWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", ShotElixirWeb do
    pipe_through :api
  end
end
