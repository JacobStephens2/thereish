defmodule MeaningGame.Chronicle.Page do
  @moduledoc """
  A Page as the Chronicle holds it: the authored document, why it ended, and the
  number the players were shown when it did.

  Written once, when the Page closes, and never touched again. `document` is the
  Page as the Author wrote it — Anchors today, more once there is an Author —
  kept as JSONB so that a contract which is still growing does not need a
  migration every time it does (ADR-0003).
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chronicle_pages" do
    field :document, :map
    field :closed_because, :string
    field :melded, :boolean
    field :closeness, :integer
    field :opened_at, :utc_datetime_usec
    field :closed_at, :utc_datetime_usec

    belongs_to :room, MeaningGame.Rooms.Room
    has_many :attempts, MeaningGame.Chronicle.Attempt, preload_order: [asc: :number]

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(page, attrs) do
    page
    |> cast(attrs, [
      :room_id,
      :document,
      :closed_because,
      :melded,
      :closeness,
      :opened_at,
      :closed_at
    ])
    |> validate_required([
      :room_id,
      :document,
      :closed_because,
      :melded,
      :opened_at,
      :closed_at
    ])
  end
end
