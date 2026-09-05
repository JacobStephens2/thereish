defmodule MeaningGame.Chronicle.Recap do
  @moduledoc """
  What the Scribe wrote about one closed Page.

  Two pieces of prose and the provenance of both. `recap` is the evening in the
  players' own words; `callback` is the line that reaches back to an earlier
  Page, and is null on an evening with nothing behind it rather than an empty
  string.

  Written once and never touched again, like everything else here (ADR-0003).
  Players edit a recap the way they edit anything else in the Chronicle: with a
  correction row against it (design law 5), which the book reads over the top.
  Running the Scribe again writes a second row rather than replacing the first,
  and the book reads the latest — the paragraph the couple were shown last month
  is still in the log.

  It carries no closeness and no band on purpose. The recap tells the story; the
  grade belongs to the Verdict and a recap never rewrites one (ADR-0006).
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chronicle_recaps" do
    field :recap, :string
    field :callback, :string
    field :model, :string
    field :prompt_version, :string
    field :cost_usd, :float
    field :latency_ms, :integer
    field :attempts, :integer

    belongs_to :room, MeaningGame.Rooms.Room
    belongs_to :page, MeaningGame.Chronicle.Page

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(recap, attrs) do
    recap
    |> cast(attrs, [
      :room_id,
      :page_id,
      :recap,
      :callback,
      :model,
      :prompt_version,
      :cost_usd,
      :latency_ms,
      :attempts
    ])
    |> validate_required([:room_id, :page_id, :recap])
  end
end
