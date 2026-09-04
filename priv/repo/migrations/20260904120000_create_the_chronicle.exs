defmodule MeaningGame.Repo.Migrations.CreateTheChronicle do
  use Ecto.Migration

  # The Chronicle is append-only, so no table here has an `updated_at` — a row
  # that could be updated would have one, and none of these can be. Nothing in
  # the application writes an UPDATE or a DELETE against them, and the couple
  # correcting the record later will be another row rather than an edit to one of
  # these. Every reference is `on_delete: :restrict` for the same reason: a Seat
  # cannot be deleted out from under the record of what it wrote.
  #
  # Rows reference Seats and never Accounts (ADR-0007). An Account may claim a
  # Seat later, and when it does, everything written here comes with it.
  def change do
    create table(:chronicle_pages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_id, references(:rooms, type: :binary_id, on_delete: :restrict), null: false

      # The authored Page as it was written — Anchors today, and the Bait, the
      # deep Bridges and the pre-graded table once the Author exists. JSONB
      # because the contract is the Author's and will grow (ADR-0003).
      add :document, :map, null: false

      add :closed_because, :text, null: false
      add :melded, :boolean, null: false
      # The number the players were shown, nil when nothing could be graded.
      add :closeness, :integer
      add :opened_at, :utc_datetime_usec, null: false
      add :closed_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:chronicle_pages, [:room_id, :closed_at])

    create table(:chronicle_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :page_id, references(:chronicle_pages, type: :binary_id, on_delete: :restrict),
        null: false

      add :number, :integer, null: false
      # What this attempt hung between: the Page's own Anchors on the first, and
      # the previous attempt's failed Bridges on every one after it.
      add :anchors, {:array, :text}, null: false
      add :closeness, :integer
      add :melded, :boolean, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:chronicle_attempts, [:page_id, :number])

    create table(:chronicle_bridges, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :attempt_id, references(:chronicle_attempts, type: :binary_id, on_delete: :restrict),
        null: false

      add :seat_id, references(:seats, type: :binary_id, on_delete: :restrict), null: false
      add :bridge, :text, null: false
      # Where this Seat sat in the roster, because the order the Bridges are read
      # back in is the order they were shown in. Inserts inside one transaction
      # cannot be told apart by their timestamps, so the order is a column.
      add :position, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:chronicle_bridges, [:attempt_id, :seat_id])
    create index(:chronicle_bridges, [:seat_id])

    create table(:chronicle_verdicts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :attempt_id, references(:chronicle_attempts, type: :binary_id, on_delete: :restrict),
        null: false

      # The two Seats this grade was about, in roster order, with `bridges`
      # holding what each of them wrote in the same order. An array rather than
      # two columns, so that nothing here has to believe a pair is what a Room
      # is made of.
      add :seat_ids, {:array, :binary_id}, null: false
      add :bridges, {:array, :text}, null: false
      add :graded, :boolean, null: false
      add :closeness, :integer
      add :band, :text
      add :reasoning, :text
      # Which pair of the attempt's pairs this was, for the same reason a Bridge
      # carries one.
      add :position, :integer, null: false

      # Provenance. The model policy stays measured only if every grade says
      # which model gave it, at what prompt version, how long it took and what
      # it cost.
      add :model, :text
      add :prompt_version, :text
      add :latency_ms, :integer
      add :cost_usd, :decimal

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:chronicle_verdicts, [:attempt_id])
  end
end
