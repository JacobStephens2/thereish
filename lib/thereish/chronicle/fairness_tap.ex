defmodule Thereish.Chronicle.FairnessTap do
  @moduledoc """
  A single fairness tap from a Seat evaluating an assayed grade.

  Accumulates into a labelled set used to calibrate the live Assayer,
  set the meld threshold, and calibrate band boundaries against how
  the couple actually judges closeness (ADR-0005, ticket 11).

  Labels are per Seat: two players can disagree about the same grade.
  The authenticated admin may review any Attempt with source "admin".
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_labels ["fair", "too_kind", "too_harsh"]
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
    |> validate_inclusion(:label, @valid_labels)
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
