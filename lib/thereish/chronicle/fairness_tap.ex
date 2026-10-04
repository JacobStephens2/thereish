defmodule Thereish.Chronicle.FairnessTap do
  @moduledoc """
  One Opinion row: a Seat's or the admin's reading of an assayed grade, as
  recorded. The table keeps its old name, fairness taps.

  The rules for building, reading and counting these rows live in
  `Thereish.Chronicle.Opinion`; this schema only casts and validates one.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Thereish.Chronicle.Opinion

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_sources ["participant", "admin"]

  schema "chronicle_fairness_taps" do
    field :attempt_number, :integer
    field :bookends, {:array, :string}
    field :bridges, {:array, :string}
    field :closeness, :integer
    field :grade, :integer, virtual: true
    field :band, :string
    field :model, :string
    field :prompt_version, :string
    field :label, :string
    field :source, :string, default: "participant"

    belongs_to :room, Thereish.Rooms.Room
    belongs_to :page, Thereish.Chronicle.Page
    belongs_to :seat, Thereish.Rooms.Seat
    belongs_to :admin, Thereish.Admin.Identity, foreign_key: :admin_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(tap, attrs) do
    attrs =
      case attrs do
        %{closeness: _} -> attrs
        %{"closeness" => _} -> attrs
        %{grade: g} -> Map.put(attrs, :closeness, g)
        %{"grade" => g} -> Map.put(attrs, "closeness", g)
        _ -> attrs
      end

    tap
    |> cast(attrs, [
      :room_id,
      :page_id,
      :seat_id,
      :admin_id,
      :attempt_number,
      :bookends,
      :bridges,
      :closeness,
      :band,
      :model,
      :prompt_version,
      :label,
      :source
    ])
    |> validate_required([
      :room_id,
      :attempt_number,
      :bookends,
      :bridges,
      :label
    ])
    |> validate_inclusion(:label, Opinion.labels())
    |> validate_inclusion(:source, @valid_sources)
    |> require_reviewer()
    |> populate_grade()
  end

  defp require_reviewer(changeset) do
    case get_field(changeset, :source) || "participant" do
      "admin" ->
        changeset
        |> validate_required([:admin_id])
        |> put_change(:seat_id, nil)

      _ ->
        changeset
        |> validate_required([:seat_id])
        |> put_change(:admin_id, nil)
    end
  end

  defp populate_grade(changeset) do
    case get_field(changeset, :closeness) do
      nil -> changeset
      val -> put_change(changeset, :grade, val)
    end
  end
end
