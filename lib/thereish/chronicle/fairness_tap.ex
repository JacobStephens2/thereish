defmodule Thereish.Chronicle.FairnessTap do
  @moduledoc """
  A single fairness tap from a Seat evaluating an assayed grade.

  Accumulates into a labelled set used to calibrate the live Assayer,
  set the meld threshold, and calibrate band boundaries against how
  the couple actually judges closeness (ADR-0005, ticket 11).

  Labels are per Seat: two players can disagree about the same grade.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_labels ["fair", "too_kind", "too_harsh"]

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

    belongs_to :room, Thereish.Rooms.Room
    belongs_to :page, Thereish.Chronicle.Page
    belongs_to :seat, Thereish.Rooms.Seat

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc "Valid label values: fair, too_kind, too_harsh."
  def valid_labels, do: @valid_labels

  @doc "Human-readable representation of a fairness label."
  def label_human(:fair), do: "fair"
  def label_human("fair"), do: "fair"
  def label_human(:too_kind), do: "too kind"
  def label_human("too_kind"), do: "too kind"
  def label_human(:too_harsh), do: "too harsh"
  def label_human("too_harsh"), do: "too harsh"
  def label_human(other), do: to_string(other)

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
      :attempt_number,
      :bookends,
      :bridges,
      :closeness,
      :band,
      :model,
      :prompt_version,
      :label
    ])
    |> validate_required([
      :room_id,
      :seat_id,
      :attempt_number,
      :bookends,
      :bridges,
      :label
    ])
    |> validate_inclusion(:label, @valid_labels)
    |> populate_grade()
  end

  defp populate_grade(changeset) do
    case get_field(changeset, :closeness) do
      nil -> changeset
      val -> put_change(changeset, :grade, val)
    end
  end
end
