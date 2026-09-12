defmodule Thereish.Admin.Token do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Query

  alias Thereish.Admin.Identity

  @hash_algorithm :sha256
  @rand_size 32
  @session_validity_in_days 60
  @reset_password_validity_in_days 1

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "admin_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string

    belongs_to :identity, Identity, foreign_key: :admin_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def build_session_token(identity) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %__MODULE__{token: hash(token), context: "session", admin_id: identity.id}}
  end

  def verify_session_token_query(token) do
    hashed = hash(token)

    from t in __MODULE__,
      join: identity in assoc(t, :identity),
      where: t.token == ^hashed and t.context == "session",
      where: t.inserted_at > ago(@session_validity_in_days, "day"),
      select: identity
  end

  def build_email_token(identity, context) do
    token = :crypto.strong_rand_bytes(@rand_size)
    encoded = Base.url_encode64(token, padding: false)

    {encoded,
     %__MODULE__{
       token: hash(token),
       context: context,
       sent_to: identity.email,
       admin_id: identity.id
     }}
  end

  def verify_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded} ->
        hashed = hash(decoded)
        days = days_for_context(context)

        query =
          from t in __MODULE__,
            join: identity in assoc(t, :identity),
            where: t.token == ^hashed and t.context == ^context,
            where: t.inserted_at > ago(^days, "day") and t.sent_to == identity.email,
            select: identity

        {:ok, query}

      :error ->
        :error
    end
  end

  def by_identity_and_contexts_query(identity, :all) do
    from t in __MODULE__, where: t.admin_id == ^identity.id
  end

  def hash(token), do: :crypto.hash(@hash_algorithm, token)

  defp days_for_context("reset_password"), do: @reset_password_validity_in_days
end
