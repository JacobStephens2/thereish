defmodule Thereish.Admin do
  @moduledoc """
  The operator identity: email/password sign-in and password reset.

  There is one identity (`jacob@stephens.page`). This is not player Account
  registration or history claiming (ADR-0017).
  """

  import Ecto.Query
  import Swoosh.Email, except: [from: 2]

  alias Thereish.Admin.Identity
  alias Thereish.Admin.Token
  alias Thereish.Mailer
  alias Thereish.Repo

  @doc "The configured operator email."
  def email do
    Application.get_env(:thereish, :admin, [])
    |> Keyword.get(:email, "jacob@stephens.page")
  end

  def get_identity_by_email(given) when is_binary(given) do
    if String.downcase(given) == String.downcase(email()) do
      Repo.get_by(Identity, email: email())
    end
  end

  def get_identity_by_email(_), do: nil

  def get_identity_by_email_and_password(given, password)
      when is_binary(given) and is_binary(password) do
    identity = get_identity_by_email(given)
    if Identity.valid_password?(identity, password), do: identity
  end

  def get_identity_by_email_and_password(_, password) when is_binary(password) do
    Identity.valid_password?(nil, password)
    nil
  end

  def get_identity_by_session_token(token) when is_binary(token) do
    Token.verify_session_token_query(token) |> Repo.one()
  end

  def get_identity_by_session_token(_), do: nil

  def generate_session_token(%Identity{} = identity) do
    {token, struct} = Token.build_session_token(identity)
    Repo.insert!(struct)
    token
  end

  def delete_session_token(token) when is_binary(token) do
    hashed = Token.hash(token)

    Repo.delete_all(from t in Token, where: t.token == ^hashed and t.context == "session")

    :ok
  end

  def get_identity_by_reset_password_token(token) when is_binary(token) do
    case Token.verify_email_token_query(token, "reset_password") do
      {:ok, query} -> Repo.one(query)
      :error -> nil
    end
  end

  def change_password(%Identity{} = identity, attrs \\ %{}) do
    Identity.password_changeset(identity, attrs, hash_password: false)
  end

  def reset_password(%Identity{} = identity, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:identity, Identity.password_changeset(identity, attrs))
    |> Ecto.Multi.delete_all(:tokens, Token.by_identity_and_contexts_query(identity, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{identity: identity}} -> {:ok, identity}
      {:error, :identity, changeset, _} -> {:error, changeset}
    end
  end

  def deliver_reset_password_instructions(%Identity{} = identity, url_fun)
      when is_function(url_fun, 1) do
    {encoded, struct} = Token.build_email_token(identity, "reset_password")
    Repo.insert!(struct)

    new()
    |> to(identity.email)
    |> Swoosh.Email.from(from_address())
    |> subject("Set your Thereish operator password")
    |> text_body("""
    Set your Thereish operator password:

    #{url_fun.(encoded)}

    If you did not ask for this, ignore it.
    """)
    |> Mailer.deliver()
  end

  defp from_address do
    Application.get_env(:thereish, :notice, [])[:from] || "thereish@thereish.app"
  end
end
