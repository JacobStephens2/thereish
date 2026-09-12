defmodule Thereish.AdminFixtures do
  @moduledoc """
  The one operator identity, with a password only when a test needs to sign in.
  """

  alias Thereish.Admin
  alias Thereish.Admin.Identity
  alias Thereish.Repo

  def admin_email, do: Admin.email()
  def valid_admin_password, do: "a-long-enough-password"

  def identity do
    Repo.get_by!(Identity, email: admin_email())
  end

  def identity_with_password(password \\ valid_admin_password()) do
    identity = identity()

    {:ok, identity} =
      Admin.reset_password(identity, %{
        "password" => password,
        "password_confirmation" => password
      })

    identity
  end
end
