defmodule MeaningGame.Repo do
  use Ecto.Repo,
    otp_app: :meaning_game,
    adapter: Ecto.Adapters.Postgres
end
