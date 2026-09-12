defmodule ThereishWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use ThereishWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint ThereishWeb.Endpoint

      use ThereishWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import ThereishWeb.ConnCase
    end
  end

  setup tags do
    Thereish.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Signs the conn in as the operator identity, setting a password if it has none.
  """
  def log_in_admin(conn, opts \\ []) do
    password = Keyword.get(opts, :password, Thereish.AdminFixtures.valid_admin_password())
    identity = Thereish.AdminFixtures.identity_with_password(password)
    token = Thereish.Admin.generate_session_token(identity)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session("admin_token", token)
  end
end
