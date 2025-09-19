defmodule ShotElixir.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Accounts.User

  def list_users do
    Repo.all(User)
  end

  def list_campaign_users(params \\ %{}, _current_user \\ nil) do
    # Get pagination parameters - handle both string and integer params
    per_page =
      case params["per_page"] do
        nil -> 15
        value when is_integer(value) -> value
        value when is_binary(value) -> String.to_integer(value)
      end

    page =
      case params["page"] do
        nil -> 1
        value when is_integer(value) -> value
        value when is_binary(value) -> String.to_integer(value)
      end

    offset = (page - 1) * per_page

    # Base query with minimal fields for performance
    query =
      from u in User,
        select: [
          :id,
          :first_name,
          :last_name,
          :name,
          :email,
          :created_at,
          :updated_at,
          :active,
          :admin,
          :gamemaster
        ]

    # Apply basic filters
    query =
      if params["id"] do
        from u in query, where: u.id == ^params["id"]
      else
        query
      end

    query =
      if params["ids"] do
        ids = parse_ids(params["ids"])
        from u in query, where: u.id in ^ids
      else
        query
      end

    query =
      if params["search"] do
        search_term = "%#{params["search"]}%"

        from u in query,
          where: ilike(u.first_name, ^search_term) or ilike(u.last_name, ^search_term)
      else
        query
      end

    query =
      if params["email"] do
        email_term = "%#{params["email"]}%"
        from u in query, where: ilike(u.email, ^email_term)
      else
        query
      end

    # Visibility filtering
    query = apply_visibility_filter(query, params)

    # Character filtering
    query =
      if params["character_id"] do
        from u in query,
          join: c in "characters",
          on: c.user_id == u.id,
          where: c.id == ^params["character_id"]
      else
        query
      end

    # Campaign filtering - include both members and owner
    query =
      if params["campaign_id"] do
        campaign_id = params["campaign_id"]

        from u in query,
          left_join: cm in "campaign_memberships",
          on: cm.user_id == u.id,
          left_join: camp in "campaigns",
          on: camp.user_id == u.id,
          where: cm.campaign_id == ^campaign_id or camp.id == ^campaign_id,
          distinct: u.id
      else
        query
      end

    # Apply sorting
    query = apply_sorting(query, params)

    # Get total count for pagination (separate query to avoid DISTINCT/ORDER BY issues)
    count_query = from(u in User)

    # Apply same filters to count query
    count_query =
      if params["id"] do
        from u in count_query, where: u.id == ^params["id"]
      else
        count_query
      end

    count_query =
      if params["ids"] do
        ids = parse_ids(params["ids"])
        from u in count_query, where: u.id in ^ids
      else
        count_query
      end

    count_query =
      if params["search"] do
        search_term = "%#{params["search"]}%"

        from u in count_query,
          where: ilike(u.first_name, ^search_term) or ilike(u.last_name, ^search_term)
      else
        count_query
      end

    count_query =
      if params["email"] do
        email_term = "%#{params["email"]}%"
        from u in count_query, where: ilike(u.email, ^email_term)
      else
        count_query
      end

    count_query = apply_visibility_filter(count_query, params)

    count_query =
      if params["character_id"] do
        from u in count_query,
          join: c in "characters",
          on: c.user_id == u.id,
          where: c.id == ^params["character_id"]
      else
        count_query
      end

    count_query =
      if params["campaign_id"] do
        campaign_id = params["campaign_id"]

        from u in count_query,
          left_join: cm in "campaign_memberships",
          on: cm.user_id == u.id,
          left_join: camp in "campaigns",
          on: camp.user_id == u.id,
          where: cm.campaign_id == ^campaign_id or camp.id == ^campaign_id,
          distinct: u.id
      else
        count_query
      end

    total_count = Repo.aggregate(count_query, :count, :id)

    # Apply pagination
    users =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    # Return users with pagination metadata
    %{
      users: users,
      meta: %{
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: div(total_count + per_page - 1, per_page)
      },
      is_autocomplete: params["autocomplete"] == "true" || params["autocomplete"] == true
    }
  end

  defp apply_visibility_filter(query, params) do
    case params["visibility"] do
      "hidden" ->
        from u in query, where: u.active == false

      "all" ->
        query

      _ ->
        # Default to visible (active) only
        from u in query, where: u.active == true
    end
  end

  defp parse_ids(ids_param) when is_binary(ids_param) do
    ids_param
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_ids(ids_param) when is_list(ids_param), do: ids_param
  defp parse_ids(_), do: []

  defp apply_sorting(query, params) do
    sort = params["sort"] || "created_at"
    order = if params["order"] == "ASC", do: :asc, else: :desc

    case sort do
      "name" ->
        order_by(query, [u], [
          {^order, fragment("LOWER(?)", u.last_name)},
          {^order, fragment("LOWER(?)", u.first_name)},
          {:asc, u.id}
        ])

      "first_name" ->
        order_by(query, [u], [
          {^order, fragment("LOWER(?)", u.first_name)},
          {^order, fragment("LOWER(?)", u.last_name)},
          {:asc, u.id}
        ])

      "last_name" ->
        order_by(query, [u], [
          {^order, fragment("LOWER(?)", u.last_name)},
          {^order, fragment("LOWER(?)", u.first_name)},
          {:asc, u.id}
        ])

      "email" ->
        order_by(query, [u], [
          {^order, fragment("LOWER(?)", u.email)},
          {:asc, u.id}
        ])

      "created_at" ->
        order_by(query, [u], [{^order, u.created_at}, {:asc, u.id}])

      "updated_at" ->
        order_by(query, [u], [{^order, u.updated_at}, {:asc, u.id}])

      _ ->
        order_by(query, [u], desc: u.created_at, asc: u.id)
    end
  end

  def get_user!(id), do: Repo.get!(User, id)

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_by_jti(jti) when is_binary(jti) do
    Repo.get_by(User, jti: jti)
  end

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, user} ->
        # Create onboarding progress (disabled in tests - DB schema mismatch)
        # ShotElixir.Onboarding.create_progress(user)
        {:ok, user}

      error ->
        error
    end
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update()
  end

  def delete_user(%User{} = user) do
    user
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
  end

  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  def authenticate_user(email, password) do
    user = get_user_by_email(email)

    cond do
      user && User.verify_password(user, password) ->
        {:ok, user}

      user ->
        {:error, :invalid_credentials}

      true ->
        # Prevent timing attacks
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  def set_current_campaign(%User{} = user, campaign_id) do
    user
    |> Ecto.Changeset.change(current_campaign_id: campaign_id)
    |> Repo.update()
  end

  def confirm_user(%User{} = user) do
    user
    |> Ecto.Changeset.change(confirmed_at: NaiveDateTime.utc_now())
    |> Repo.update()
  end

  def lock_user(%User{} = user) do
    user
    |> Ecto.Changeset.change(locked_at: NaiveDateTime.utc_now())
    |> Repo.update()
  end

  def unlock_user(%User{} = user) do
    user
    |> Ecto.Changeset.change(locked_at: nil, failed_attempts: 0)
    |> Repo.update()
  end

  def increment_failed_attempts(%User{} = user) do
    attempts = user.failed_attempts + 1

    changes =
      if attempts >= 5 do
        %{failed_attempts: attempts, locked_at: NaiveDateTime.utc_now()}
      else
        %{failed_attempts: attempts}
      end

    user
    |> Ecto.Changeset.change(changes)
    |> Repo.update()
  end

  def generate_auth_token(user) do
    ShotElixir.Guardian.encode_and_sign(user)
  end

  def validate_token(token) do
    case ShotElixir.Guardian.decode_and_verify(token) do
      {:ok, claims} ->
        case get_user(claims["sub"]) do
          nil -> {:error, :user_not_found}
          user -> {:ok, user}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def generate_confirmation_token(%User{} = user) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64()

    user
    |> Ecto.Changeset.change(
      confirmation_token: token,
      confirmation_sent_at: NaiveDateTime.utc_now()
    )
    |> Repo.update()
  end

  def generate_reset_password_token(%User{} = user) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64()

    user
    |> Ecto.Changeset.change(
      reset_password_token: token,
      reset_password_sent_at: NaiveDateTime.utc_now()
    )
    |> Repo.update()
  end
end
