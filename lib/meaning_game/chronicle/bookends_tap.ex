defmodule MeaningGame.Chronicle.BookendsTap do
  @moduledoc """
  A recorded tap on the Bookends written for a Page (flat, fine, or great).

  Append-only event table (ADR-0003, design law 5): no updated_at.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chronicle_bookends_taps" do
    field :page_identifier, :string
    field :label, :string
    field :bookends, {:array, :string}
    field :gives, :map
    field :author_meta, :map
    field :arm, :string

    belongs_to :room, MeaningGame.Rooms.Room
    belongs_to :page, MeaningGame.Chronicle.Page
    belongs_to :seat, MeaningGame.Rooms.Seat

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(tap, attrs) do
    attrs =
      attrs
      |> to_map()
      |> normalize_arm()
      |> normalize_page_identifier()

    tap
    |> cast(attrs, [
      :room_id,
      :page_id,
      :page_identifier,
      :seat_id,
      :label,
      :bookends,
      :gives,
      :author_meta,
      :arm
    ])
    |> validate_required([:room_id, :seat_id, :label])
    |> validate_inclusion(:label, ["flat", "fine", "great"])
  end

  defp to_map(attrs) when is_map(attrs), do: attrs
  defp to_map(_), do: %{}

  defp normalize_arm(%{arm: arm} = attrs) when is_atom(arm) and not is_nil(arm),
    do: Map.put(attrs, :arm, to_string(arm))

  defp normalize_arm(%{"arm" => arm} = attrs) when is_atom(arm) and not is_nil(arm),
    do: Map.put(attrs, "arm", to_string(arm))

  defp normalize_arm(attrs), do: attrs

  defp normalize_page_identifier(attrs) do
    id =
      attrs[:page_identifier] || attrs["page_identifier"] || attrs[:page_id] ||
        attrs["page_id"] || (attrs[:bookends] && Enum.join(attrs[:bookends], "-")) ||
        "page"

    attrs = Map.put(attrs, :page_identifier, to_string(id))

    case attrs[:page_id] || attrs["page_id"] do
      pid when is_binary(pid) ->
        if Regex.match?(
             ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
             pid
           ) do
          attrs
        else
          attrs |> Map.delete(:page_id) |> Map.delete("page_id")
        end

      _ ->
        attrs
    end
  end
end
