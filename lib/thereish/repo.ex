defmodule Thereish.Repo do
  use Ecto.Repo,
    otp_app: :thereish,
    adapter: Ecto.Adapters.Postgres
end
