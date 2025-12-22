defmodule Mix.Tasks.ExportWeaponImages do
  @moduledoc """
  Exports active_storage records for weapons in the master template campaign.

  Run this against production to get the SQL INSERT statements for weapon images,
  then add them to priv/repo/seeds/master_template.sql

  Usage:
    mix export_weapon_images
  """

  use Mix.Task

  alias ShotElixir.Repo
  import Ecto.Query

  @shortdoc "Export weapon image active_storage records as SQL"

  def run(_args) do
    Mix.Task.run("app.start")

    # Get the master template campaign
    master_campaign =
      Repo.one(
        from c in ShotElixir.Campaigns.Campaign,
          where: c.is_master_template == true
      )

    if is_nil(master_campaign) do
      IO.puts("-- ERROR: No master template campaign found!")
      System.halt(1)
    end

    IO.puts("-- Exporting weapon images for master template: #{master_campaign.name}")
    IO.puts("-- Campaign ID: #{master_campaign.id}")
    IO.puts("")

    # Get all weapons in the master template
    weapons =
      Repo.all(
        from w in ShotElixir.Weapons.Weapon,
          where: w.campaign_id == ^master_campaign.id and w.active == true,
          select: w.id
      )

    IO.puts("-- Found #{length(weapons)} weapons in master template")
    IO.puts("")

    # Get attachments for these weapons
    weapon_ids = Enum.map(weapons, &to_string/1)

    attachments =
      Repo.all(
        from a in ShotElixir.ActiveStorage.Attachment,
          join: b in ShotElixir.ActiveStorage.Blob,
          on: a.blob_id == b.id,
          where: a.record_type == "Weapon" and a.record_id in ^weapon_ids,
          select: {a, b}
      )

    IO.puts("-- Found #{length(attachments)} weapon image attachments")
    IO.puts("")

    if length(attachments) == 0 do
      IO.puts(
        "-- WARNING: No weapon images found! Make sure weapons have images uploaded in this environment."
      )
    else
      IO.puts("-- Active Storage Blobs for Weapons")
      IO.puts("")

      # Output blob inserts
      Enum.each(attachments, fn {_attachment, blob} ->
        metadata = escape_string(blob.metadata || "{}")
        filename = escape_string(blob.filename)
        key = escape_string(blob.key)
        content_type = escape_string(blob.content_type || "image/png")
        service_name = escape_string(blob.service_name || "imagekit")
        checksum = escape_string(blob.checksum || "")

        IO.puts(
          "INSERT INTO active_storage_blobs (id, key, filename, content_type, metadata, service_name, byte_size, checksum, created_at) VALUES (#{blob.id}, '#{key}', '#{filename}', '#{content_type}', '#{metadata}', '#{service_name}', #{blob.byte_size || 0}, '#{checksum}', '#{format_timestamp(blob.created_at)}') ON CONFLICT (id) DO NOTHING;"
        )
      end)

      IO.puts("")
      IO.puts("-- Active Storage Attachments for Weapons")
      IO.puts("")

      # Output attachment inserts
      Enum.each(attachments, fn {attachment, _blob} ->
        name = escape_string(attachment.name)
        record_type = escape_string(attachment.record_type)

        IO.puts(
          "INSERT INTO active_storage_attachments (id, name, record_type, record_id, blob_id, created_at) VALUES (#{attachment.id}, '#{name}', '#{record_type}', '#{attachment.record_id}', #{attachment.blob_id}, '#{format_timestamp(attachment.created_at)}') ON CONFLICT (id) DO NOTHING;"
        )
      end)
    end

    IO.puts("")
    IO.puts("-- Export complete!")
  end

  defp escape_string(nil), do: ""

  defp escape_string(str) when is_binary(str) do
    str
    |> String.replace("'", "''")
    |> String.replace("\\", "\\\\")
  end

  defp escape_string(other), do: to_string(other)

  defp format_timestamp(nil), do: "NOW()"

  defp format_timestamp(%NaiveDateTime{} = dt) do
    NaiveDateTime.to_string(dt)
  end

  defp format_timestamp(%DateTime{} = dt) do
    DateTime.to_naive(dt) |> NaiveDateTime.to_string()
  end

  defp format_timestamp(other), do: to_string(other)
end
