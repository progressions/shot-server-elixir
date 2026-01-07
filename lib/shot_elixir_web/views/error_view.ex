defmodule ShotElixirWeb.ErrorView do
  def render("401.json", _assigns) do
    %{error: "Not authenticated"}
  end

  def render("403.json", _assigns) do
    %{error: "Forbidden"}
  end

  def render("404.json", _assigns) do
    %{error: "Not found"}
  end

  def render("422.json", _assigns) do
    %{error: "Unprocessable entity"}
  end

  def render("500.json", _assigns) do
    %{error: "Internal server error"}
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      errors:
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Enum.reduce(opts, msg, fn {key, value}, acc ->
            String.replace(acc, "%{#{key}}", to_string(value))
          end)
        end)
    }
  end

  def render("error.json", %{error: error}) do
    %{error: error}
  end

  # Default handler for any other error
  def template_not_found(template, _assigns) do
    %{error: Phoenix.Controller.status_message_from_template(template)}
  end
end
