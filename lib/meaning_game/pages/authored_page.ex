defmodule MeaningGame.Pages.AuthoredPage do
  @moduledoc """
  An authored Page stored in the pre-generated pool.

  Carries Bookends, the Bait, at least two deep Bridges, likely Bridges with
  `why_these` as the pre-graded table, fallback band scripts, and provenance meta.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "authored_pages" do
    field :page_id, :string
    field :chapter, :string
    field :give, :string
    field :theme, :string
    field :bookends, {:array, :string}
    field :bait, :string
    field :deep_bridges, {:array, :string}
    field :likely_bridges, {:array, :string}
    field :why_these, :string
    field :band_scripts, :map
    field :meta, :map

    field :played_at, :utc_datetime_usec
    field :played_room_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @fields [
    :page_id,
    :chapter,
    :give,
    :theme,
    :bookends,
    :bait,
    :deep_bridges,
    :likely_bridges,
    :why_these,
    :band_scripts,
    :meta,
    :played_at,
    :played_room_id
  ]

  def changeset(authored_page, attrs) do
    authored_page
    |> cast(attrs, @fields)
    |> validate_required([
      :page_id,
      :chapter,
      :theme,
      :bookends,
      :bait,
      :deep_bridges,
      :likely_bridges,
      :why_these,
      :band_scripts,
      :meta
    ])
    |> unique_constraint(:page_id)
  end

  def mark_played_changeset(authored_page, room_id) do
    change(authored_page, played_at: DateTime.utc_now(), played_room_id: room_id)
  end
end
