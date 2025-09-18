defmodule ShotElixirWeb.FallbackController do
  use ShotElixirWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(ShotElixirWeb.ErrorView)
    |> render("error.json", changeset: changeset)
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(ShotElixirWeb.ErrorView)
    |> render("404.json")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(ShotElixirWeb.ErrorView)
    |> render("401.json")
  end

  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> put_view(ShotElixirWeb.ErrorView)
    |> render("403.json")
  end
end
