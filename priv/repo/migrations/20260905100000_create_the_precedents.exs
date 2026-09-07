defmodule Thereish.Repo.Migrations.CreateThePrecedents do
  use Ecto.Migration

  # The verdict cache is the precedent (ADR-0006, design law 1). When the couple
  # plays the same Anchors and writes the same Bridges a month later, the game
  # grades exactly as it graded the first time: consistency beats accuracy.
  #
  # Keyed by model, prompt version, and normalized inputs. Both orderings of a
  # pair collapse to a single key, and normalization (NFC, downcase, whitespace
  # collapse) ensures that trivial surface differences do not fork a key.
  #
  # Nothing silently rewrites a precedent: offline annotations never touch the
  # cache. Only a joint player overrule (design law 3) will rewrite it.
  def change do
    create table(:precedents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :text, null: false
      add :model, :text, null: false
      add :prompt_version, :text, null: false
      add :anchors, {:array, :text}, null: false
      add :bridges, {:array, :text}, null: false
      add :closeness, :integer, null: false
      add :reasoning, :text, null: false
      add :quip, :text, null: false
      add :forward, :integer
      add :reverse, :integer
      add :reasoning_reverse, :text
      add :cost_usd, :decimal

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:precedents, [:key])
  end
end
