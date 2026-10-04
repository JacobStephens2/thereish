defmodule Thereish.Chronicle.Page do
  @moduledoc """
  A Page as the Chronicle holds it: the authored document, why it ended, and the
  number the players were shown when it did.

  Written once, when the Page closes, and never touched again. `document` is the
  Page as it was written at the table, a `Thereish.Chronicle.Document`, kept as
  JSONB so that a contract which is still growing does not need a migration
  every time it does (ADR-0003).
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chronicle_pages" do
    field :document, Thereish.Chronicle.Document
    field :author_meta, :map
    field :music_meta, Thereish.Foley.Track
    field :vamp_meta, Thereish.Foley.Vamp
    field :masks_meta, {:map, Thereish.Mask}
    field :closed_because, :string
    field :melded, :boolean
    field :closeness, :integer
    field :opened_at, :utc_datetime_usec
    field :closed_at, :utc_datetime_usec
    field :revealed_at, :utc_datetime_usec

    belongs_to :room, Thereish.Rooms.Room
    has_many :gives, Thereish.Chronicle.Give, preload_order: [asc: :order]
    has_many :attempts, Thereish.Chronicle.Attempt, preload_order: [asc: :number]
    has_many :overrules, Thereish.Chronicle.Overrule, preload_order: [asc: :inserted_at]
    has_many :corrections, Thereish.Chronicle.Correction, preload_order: [asc: :inserted_at]
    has_many :fairness_taps, Thereish.Chronicle.FairnessTap, preload_order: [asc: :inserted_at]

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(page, attrs) do
    page
    |> cast(attrs, [
      :room_id,
      :document,
      :author_meta,
      :music_meta,
      :vamp_meta,
      :masks_meta,
      :closed_because,
      :melded,
      :closeness,
      :opened_at,
      :closed_at,
      :revealed_at
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
