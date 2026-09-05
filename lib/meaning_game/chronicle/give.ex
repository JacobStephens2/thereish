defmodule MeaningGame.Chronicle.Give do
  @moduledoc """
  What setting (Give) one Seat offered for a Page.

  Recorded in roster order, referencing the Seat that gave it.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chronicle_gives" do
    field :text, :string
    field :order, :integer

    belongs_to :page, MeaningGame.Chronicle.Page
    belongs_to :seat, MeaningGame.Rooms.Seat

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(give, attrs) do
    give
    |> cast(attrs, [:page_id, :seat_id, :text, :order])
    |> validate_required([:page_id, :seat_id, :text, :order])
    |> unique_constraint([:page_id, :seat_id])
  end
end
