defmodule Thereish.Chronicle.Opinion do
  @moduledoc """
  The rules for an Opinion: a Seat's or the admin's Too harsh / Fair / Too kind
  reading of one Attempt's grade, as the Assayer gave it before any overrule
  (ADR-0019).

  An Opinion is given during play at the reveal or afterwards in the Chronicle.
  Both paths build their row here, from a `t:graded/0` Attempt the caller reads
  out of its own source: the Game from its state, the Chronicle from rows plus
  the Attempt's overrule. Every reader asks here which rows are current, so a
  reviewer's latest Opinion of an Attempt replaces their earlier ones wherever
  Opinions are shown or counted. The rows themselves are never deleted or
  updated (ADR-0003).

  Pure: no Repo and no Room. Whether a tap may happen yet is the Game's rule,
  and whether an admin identity exists is the Chronicle's.
  """

  alias Thereish.Ladder

  @labels ["too_harsh", "fair", "too_kind"]

  @typedoc "One of `labels/0`."
  @type label :: String.t()

  @typedoc "Who gives an Opinion: a Seat that played the Attempt, or the admin."
  @type reviewer :: {:participant, Ecto.UUID.t()} | {:admin, Ecto.UUID.t()}

  @typedoc """
  An Attempt as an Opinion reads it. `closeness` is the grade as it stands and
  `machine_closeness` the Assayer's grade before an overrule, `nil` when there
  was none. `band` is the stored band. `participant_ids` are the Seats that
  wrote a Bridge on it. `page_id` is `nil` during play, before the Page reaches
  the Chronicle.
  """
  @type graded :: %{
          required(:participant_ids) => [Ecto.UUID.t()],
          required(:attempt_number) => pos_integer(),
          required(:bookends) => [String.t()],
          required(:bridges) => [String.t()],
          optional(:page_id) => Ecto.UUID.t() | nil,
          optional(:closeness) => integer() | nil,
          optional(:machine_closeness) => integer() | nil,
          optional(:band) => String.t() | nil,
          optional(:model) => String.t() | nil,
          optional(:prompt_version) => String.t() | nil
        }

  @doc "The labels, in the order of the scale: too harsh, fair, too kind."
  @spec labels() :: [label()]
  def labels, do: @labels

  @doc """
  Reads a label from an atom or a string, with an underscore or a space,
  trimmed and in any case.
  """
  @spec label(term()) :: {:ok, label()} | {:error, :invalid_label}
  def label(label) when is_atom(label) and not is_nil(label), do: label(Atom.to_string(label))

  def label(label) when is_binary(label) do
    parsed = label |> String.trim() |> String.downcase() |> String.replace(" ", "_")
    if parsed in @labels, do: {:ok, parsed}, else: {:error, :invalid_label}
  end

  def label(_label), do: {:error, :invalid_label}

  @doc "Words a label for people: `\"too_kind\"` reads as \"too kind\"."
  @spec human(label() | atom()) :: String.t()
  def human(label) do
    case label(label) do
      {:ok, parsed} -> String.replace(parsed, "_", " ")
      {:error, :invalid_label} -> to_string(label)
    end
  end

  @doc """
  Builds the row to record for one reviewer's Opinion of a graded Attempt.

  Refuses a Seat that wrote no Bridge on it (`:not_a_participant`), an Attempt
  with neither a grade nor a band (`:not_assayed`) and an unknown label.
  """
  @spec new(graded(), reviewer(), term()) ::
          {:ok, map()} | {:error, :not_a_participant | :not_assayed | :invalid_label}
  def new(graded, reviewer, label) do
    grade = Map.get(graded, :machine_closeness) || Map.get(graded, :closeness)
    band = if grade, do: to_string(Ladder.read(grade).band), else: Map.get(graded, :band)

    with :ok <- if(may_give?(graded, reviewer), do: :ok, else: {:error, :not_a_participant}),
         :ok <- if(band, do: :ok, else: {:error, :not_assayed}),
         {:ok, label} <- label(label) do
      {source, seat_id, admin_id} =
        case reviewer do
          {:participant, seat_id} -> {"participant", seat_id, nil}
          {:admin, admin_id} -> {"admin", nil, admin_id}
        end

      {:ok,
       %{
         page_id: Map.get(graded, :page_id),
         attempt_number: graded.attempt_number,
         bookends: graded.bookends,
         bridges: graded.bridges,
         closeness: grade,
         band: band,
         model: Map.get(graded, :model),
         prompt_version: Map.get(graded, :prompt_version),
         label: label,
         source: source,
         seat_id: seat_id,
         admin_id: admin_id
       }}
    end
  end

  @doc """
  Whether a reviewer may give an Opinion of an Attempt: a Seat that wrote a
  Bridge on it, or the admin, who may review any Attempt.
  """
  @spec may_give?(%{participant_ids: [Ecto.UUID.t()]}, reviewer() | nil) :: boolean()
  def may_give?(_graded, {:admin, admin_id}) when is_binary(admin_id), do: true

  def may_give?(%{participant_ids: ids}, {:participant, seat_id}) when is_binary(seat_id),
    do: seat_id in ids

  def may_give?(_graded, _reviewer), do: false

  @doc """
  The current Opinions among some rows, oldest first: each reviewer's latest of
  each Attempt.

  The latest is the last row by insertion time and then id; rows without an
  insertion time keep the order they came in. An Attempt is its Room, number and Bookends, not its Page: a tap
  during play is written before its Page reaches the Chronicle, so it names
  none, and the same Seat's later retrospective Opinion still replaces it.
  """
  @spec current([row]) :: [row] when row: map()
  def current(rows) do
    rows
    |> Enum.sort(&not_after?/2)
    |> Enum.reverse()
    |> Enum.uniq_by(&{attempt_key(&1), reviewer_of(&1)})
    |> Enum.reverse()
  end

  @doc "One reviewer's current label among some Opinions, or `nil`."
  @spec of([map()], reviewer()) :: label() | nil
  def of(opinions, reviewer) do
    opinions
    |> Enum.filter(&(reviewer_of(&1) == reviewer))
    |> List.last()
    |> then(&(&1 && &1.label))
  end

  @doc """
  The labelled set for calibrating the Assayer (ADR-0005): each participant's
  current Opinion of each Attempt. The admin's reviews are left out, since the
  set measures how the table judges closeness.
  """
  @spec calibration([map()]) :: [map()]
  def calibration(rows) do
    rows
    |> participant_current()
    |> Enum.map(fn t ->
      closeness = t.closeness || Map.get(t, :grade)

      %{
        id: t.id,
        room_id: t.room_id,
        page_id: t.page_id,
        attempt_number: t.attempt_number,
        seat_id: t.seat_id,
        seat_name: seat_name(t),
        bookends: t.bookends,
        bridges: t.bridges,
        grade: closeness,
        closeness: closeness,
        band: t.band,
        model: t.model,
        prompt_version: t.prompt_version,
        label: t.label,
        inserted_at: t.inserted_at
      }
    end)
  end

  @doc "How many current participant Opinions carry each label."
  @spec tally([map()]) :: %{label() => non_neg_integer()}
  def tally(rows) do
    counts = rows |> participant_current() |> Enum.frequencies_by(&to_string(&1.label))
    Map.new(@labels, &{&1, Map.get(counts, &1, 0)})
  end

  defp participant_current(rows),
    do: rows |> current() |> Enum.filter(&match?({:participant, _}, reviewer_of(&1)))

  defp not_after?(a, b) do
    case {Map.get(a, :inserted_at), Map.get(b, :inserted_at)} do
      {%DateTime{} = at, %DateTime{} = bt} ->
        case DateTime.compare(at, bt) do
          :lt -> true
          :gt -> false
          :eq -> a.id <= b.id
        end

      _no_time ->
        true
    end
  end

  defp attempt_key(row),
    do: {Map.get(row, :room_id), Map.get(row, :attempt_number), Map.get(row, :bookends)}

  defp reviewer_of(row) do
    case Map.get(row, :source) do
      "admin" -> {:admin, Map.get(row, :admin_id)}
      _participant -> {:participant, Map.get(row, :seat_id)}
    end
  end

  defp seat_name(%{seat: %{name: name}}), do: name
  defp seat_name(_row), do: nil
end
