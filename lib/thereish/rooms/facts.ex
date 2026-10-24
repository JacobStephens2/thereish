defmodule Thereish.Rooms.Facts do
  @moduledoc """
  The Room's facts: who holds the Speaker, Quips, Full table, Split readings,
  the music setting, whether the Prologue was skipped, the Code's Quip, and the
  Prologue take playing now.

  It is pure and effect-returning like Pacing, Pages, Occupancy and Voice,
  but takes commands through one `apply/2` as the Game does. The Room builds
  it from its row, hands it each command, and gets back the new facts, the
  attributes to persist and the effects to carry out. It touches
  no database, process or PubSub. Every fact but the take is a column on the
  Room; the take is not persisted, so a restart forgets it.

  ## The Speaker

  A Speaker is held by a device token. `holds_speaker?/2` and
  `speaker_claimed?/1` are the only definitions of holding it and of it being
  claimed, and no other module compares device tokens. A nil or blank
  Speaker is unclaimed, and a nil or blank token holds nothing.

  ## The Prologue rule

  The Stage's first tap draws a take only when the Room has no Chronicle, the
  Prologue was not skipped, and no take is playing. Playing the Prologue
  draws a new take whatever came before; skipping it clears the take and
  records the skip.

  ## Effects

    * `:speaker_claimed`: tell Voice a device claimed the Speaker
    * `{:music_changed, music}`: tell Occupancy the music setting changed
    * `{:full_table_changed, enabled}`: tell the Game the Room's Full table
      rule changed
  """

  import Kernel, except: [apply: 2]

  alias Thereish.Foley.Prologue
  alias Thereish.Rooms.Room

  @persisted [:speaker, :quips, :full_table, :split_readings, :music, :prologue_skipped]
  @on_off [:quips, :full_table, :split_readings]

  @doc "Whether `fact` is one of the Room facts that is only on or off."
  defguard is_on_off(fact) when fact in @on_off

  defstruct speaker: nil,
            quips: true,
            full_table: true,
            split_readings: true,
            music: "page",
            prologue_skipped: false,
            quip: nil,
            prologue: nil

  @type take :: %{reading: String.t(), text: String.t()}
  @type on_off :: :quips | :full_table | :split_readings

  @type t :: %__MODULE__{
          speaker: String.t() | nil,
          quips: boolean(),
          full_table: boolean(),
          split_readings: boolean(),
          music: String.t(),
          prologue_skipped: boolean(),
          quip: String.t() | nil,
          prologue: take() | nil
        }

  @type command ::
          {:claim_speaker, String.t() | nil}
          | {:start_sound, String.t() | nil, has_chronicle? :: boolean()}
          | {:release_speaker, String.t() | nil}
          | {:set, on_off(), boolean()}
          | {:toggle, on_off()}
          | {:set_music, String.t() | atom()}
          | :skip_prologue
          | :play_prologue

  @typedoc """
  Something for the Room to do. Effects are descriptions: Facts performs none
  of them.
  """
  @type effect ::
          :speaker_claimed
          | {:music_changed, String.t()}
          | {:full_table_changed, boolean()}

  @typedoc "The Room-fact keys of one device's snapshot."
  @type view :: %{
          speaker?: boolean(),
          speaker_claimed?: boolean(),
          quips: boolean(),
          full_table: boolean(),
          split_readings: boolean(),
          music: String.t(),
          quip: String.t() | nil,
          prologue_skipped: boolean(),
          prologue: take() | nil,
          prologue_script: String.t()
        }

  @doc "The facts a Room's row holds, with no Prologue take playing."
  @spec new(Room.t()) :: t()
  def new(%Room{} = room) do
    %__MODULE__{
      speaker: room.speaker,
      quips: room.quips,
      full_table: room.full_table,
      split_readings: room.split_readings,
      music: room.music,
      prologue_skipped: room.prologue_skipped,
      quip: room.quip
    }
  end

  @doc """
  Runs one command. Answers the new facts, the attributes to persist (empty
  when no persisted fact changed) and the effects to carry out, or an error.
  """
  @spec apply(t(), command()) :: {:ok, t(), map(), [effect()]} | {:error, :bad_music_setting}
  def apply(%__MODULE__{} = facts, {:claim_speaker, device_token}) do
    if holds_speaker?(facts, device_token) or blank?(device_token) do
      outcome(facts, facts, [])
    else
      outcome(facts, %{facts | speaker: device_token}, [:speaker_claimed])
    end
  end

  def apply(%__MODULE__{} = facts, {:start_sound, device_token, has_chronicle?}) do
    cond do
      blank?(device_token) ->
        outcome(facts, facts, [])

      not has_chronicle? and not facts.prologue_skipped and is_nil(facts.prologue) ->
        new = %{facts | speaker: device_token, prologue: Prologue.draw_take()}
        outcome(facts, new, [:speaker_claimed])

      true ->
        outcome(facts, %{facts | speaker: device_token}, [:speaker_claimed])
    end
  end

  def apply(%__MODULE__{} = facts, {:release_speaker, device_token}) do
    if speaker_claimed?(facts) and (is_nil(device_token) or holds_speaker?(facts, device_token)) do
      outcome(facts, %{facts | speaker: nil}, [])
    else
      outcome(facts, facts, [])
    end
  end

  def apply(%__MODULE__{} = facts, {:set, fact, enabled})
      when is_on_off(fact) and is_boolean(enabled) do
    new = Map.put(facts, fact, enabled)
    outcome(facts, new, on_off_effects(fact, facts, new))
  end

  def apply(%__MODULE__{} = facts, {:toggle, fact}) when is_on_off(fact) do
    apply(facts, {:set, fact, Map.fetch!(facts, fact) != true})
  end

  def apply(%__MODULE__{} = facts, {:set_music, music}) when is_binary(music) or is_atom(music) do
    music = to_string(music)

    # Occupancy hears the setting even when it is unchanged: choosing "page"
    # again is how a Page with no Track running asks for one.
    if music in Room.music_modes() do
      outcome(facts, %{facts | music: music}, [{:music_changed, music}])
    else
      {:error, :bad_music_setting}
    end
  end

  def apply(%__MODULE__{}, {:set_music, _music}), do: {:error, :bad_music_setting}

  def apply(%__MODULE__{} = facts, :skip_prologue) do
    outcome(facts, %{facts | prologue_skipped: true, prologue: nil}, [])
  end

  def apply(%__MODULE__{} = facts, :play_prologue) do
    outcome(facts, %{facts | prologue: Prologue.draw_take()}, [])
  end

  @doc "Whether `device_token` holds the Speaker. A nil or blank token holds nothing."
  @spec holds_speaker?(t(), String.t() | nil) :: boolean()
  def holds_speaker?(%__MODULE__{} = facts, device_token) do
    speaker_claimed?(facts) and not blank?(device_token) and facts.speaker == device_token
  end

  @doc "Whether any device holds the Speaker. A nil or blank Speaker is unclaimed."
  @spec speaker_claimed?(t()) :: boolean()
  def speaker_claimed?(%__MODULE__{speaker: speaker}), do: not blank?(speaker)

  @doc "The snapshot's Room-fact keys for `device_token`. No device token appears in it."
  @spec view(t(), String.t() | nil) :: view()
  def view(%__MODULE__{} = facts, device_token) do
    %{
      speaker?: holds_speaker?(facts, device_token),
      speaker_claimed?: speaker_claimed?(facts),
      quips: facts.quips,
      full_table: facts.full_table,
      split_readings: facts.split_readings,
      music: facts.music,
      quip: facts.quip,
      prologue_skipped: facts.prologue_skipped,
      prologue: facts.prologue,
      prologue_script: Prologue.script()
    }
  end

  # The attributes to persist are the persisted facts that differ, so a
  # command that changes nothing writes nothing.
  defp outcome(old, new, effects) do
    attrs =
      for key <- @persisted, Map.fetch!(old, key) != Map.fetch!(new, key), into: %{} do
        {key, Map.fetch!(new, key)}
      end

    {:ok, new, attrs, effects}
  end

  defp on_off_effects(:full_table, %{full_table: same}, %{full_table: same}), do: []
  defp on_off_effects(:full_table, _old, new), do: [{:full_table_changed, new.full_table}]
  defp on_off_effects(:quips, _old, _new), do: []
  defp on_off_effects(:split_readings, _old, _new), do: []

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
end
