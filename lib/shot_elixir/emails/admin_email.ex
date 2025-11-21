defmodule ShotElixir.Emails.AdminEmail do
  @moduledoc """
  System and admin notification emails.

  Handles critical error notifications and other system alerts
  sent to administrators.
  """

  import Swoosh.Email
  alias ShotElixirWeb.EmailView

  @from_email "system@chiwar.net"
  @from_name "Chi War System"
  @admin_email "progressions@gmail.com"

  @doc """
  Critical error notification for blob sequence errors.
  Sent when Active Storage encounters sequence conflicts.
  """
  def blob_sequence_error(campaign, error_message) do
    timestamp = DateTime.utc_now()

    new()
    |> to(@admin_email)
    |> from({@from_name, @from_email})
    |> subject("[CRITICAL] Campaign Seeding Failed - Blob Sequence Error")
    |> header("Priority", "high")
    |> html_body(
      render_template("blob_sequence_error.html", %{
        campaign: campaign,
        error_message: error_message,
        timestamp: timestamp
      })
    )
    |> text_body(
      render_template("blob_sequence_error.text", %{
        campaign: campaign,
        error_message: error_message,
        timestamp: timestamp
      })
    )
  end

  # Private helpers

  defp render_template(template_name, assigns) do
    Phoenix.View.render_to_string(
      EmailView,
      "admin_email/#{template_name}",
      assigns
    )
  end
end
