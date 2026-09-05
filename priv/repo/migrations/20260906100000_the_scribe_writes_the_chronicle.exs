defmodule MeaningGame.Repo.Migrations.TheScribeWritesTheChronicle do
  use Ecto.Migration

  @moduledoc """
  The Scribe's recap of one closed Page, and the callback it planted.

  Append-only like every other Chronicle table (ADR-0003): a recap the players
  want changed is a correction row against it, never an update here. A Page may
  therefore carry more than one recap — the Scribe run twice, or run again after
  a prompt was changed — and the book reads the latest.
  """

  def change do
    create table(:chronicle_recaps, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :delete_all), null: false

      add :page_id, references(:chronicle_pages, type: :binary_id, on_delete: :delete_all),
        null: false

      add :recap, :text, null: false
      # Null rather than empty: an evening with nothing behind it has no
      # callback, and that is a different thing from a callback of no words.
      add :callback, :text

      add :model, :string
      add :prompt_version, :string
      add :cost_usd, :float
      add :latency_ms, :integer
      add :attempts, :integer

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:chronicle_recaps, [:room_id, :inserted_at])
    create index(:chronicle_recaps, [:page_id])
  end
end
