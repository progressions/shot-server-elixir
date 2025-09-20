defmodule ShotElixir.Models.Broadcastable do
  @moduledoc """
  Provides automatic broadcasting for model changes via Phoenix.PubSub.
  Mimics Rails Broadcastable concern behavior for ActionCable compatibility.
  """

  defmacro __using__(_opts) do
    quote do
      import ShotElixir.Models.Broadcastable

      @doc """
      Broadcasts entity changes after database commits.
      Should be called from context modules after successful operations.
      """
      def broadcast_after_commit(%Ecto.Changeset{} = changeset, action) do
        broadcast_change(changeset.data, action)
        {:ok, changeset}
      end

      def broadcast_after_commit(entity, action) do
        broadcast_change(entity, action)
        {:ok, entity}
      end

      @doc """
      Broadcasts an entity change via the BroadcastManager.
      """
      def broadcast_change(entity, action) when action in [:insert, :update, :delete] do
        ShotElixir.BroadcastManager.broadcast_entity_change(entity, action)
      end

      defoverridable broadcast_after_commit: 2, broadcast_change: 2
    end
  end

  @doc """
  Helper function to broadcast changes for entities that don't use the macro.
  """
  def broadcast(entity, action) when action in [:insert, :update, :delete] do
    ShotElixir.BroadcastManager.broadcast_entity_change(entity, action)
  end
end