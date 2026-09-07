defmodule Thereish.Chronicle.Overrule do
  @moduledoc """
  A joint player overrule recorded in the Chronicle.

  Keeps both what the machine said and what the couple said, who proposed it,
  and what the words were (design law 3).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chronicle_overrules" do
    field :attempt_number, :integer
    field :bookends, {:array, :string}
    field :bridges, {:array, :string}
    field :machine_closeness, :integer
    field :machine_reasoning, :string
    field :machine_quip, :string
    field :couple_closeness, :integer
    field :couple_reasoning, :string

    belongs_to :room, Thereish.Rooms.Room
    belongs_to :page, Thereish.Chronicle.Page
    belongs_to :proposer, Thereish.Rooms.Seat, foreign_key: :proposer_seat_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(overrule, attrs) do
    overrule
    |> cast(attrs, [
      :room_id,
      :page_id,
      :attempt_number,
      :proposer_seat_id,
      :bookends,
      :bridges,
      :machine_closeness,
      :machine_reasoning,
      :machine_quip,
      :couple_closeness,
      :couple_reasoning
    ])
    |> validate_required([
      :room_id,
      :attempt_number,
      :proposer_seat_id,
      :bookends,
      :bridges,
      :couple_closeness,
      :couple_reasoning
    ])
  end
end
