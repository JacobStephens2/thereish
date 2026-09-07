defmodule MeaningGame.Steward do
  @moduledoc """
  The one seam through which the game talks to language models.

  Nothing else in the codebase knows a provider exists. Model choice, per-role
  effort, hedging, caching, and schema validation all end up behind here; today
  the only role that has crossed it is the Assayer, and exactly two adapters
  satisfy it — `MeaningGame.Steward.Live`, which talks to a provider, and
  `MeaningGame.Steward.Fake`, which every test that is not a hand-run smoke test
  grades against. Two adapters is what makes this a seam rather than a
  hypothesis.

  Which adapter is in use is configuration, so a test and the couch differ by a
  setting rather than by a code path:

      config :meaning_game, :steward, adapter: MeaningGame.Steward.Fake

  So is what each role is answered by. Swapping the Assayer for another model,
  another effort, or another company is `config/config.exs` and nothing else
  (spec, "Operating it"):

      config :meaning_game, :steward,
        roles: [assayer: [provider: ..., model: ..., effort: ...]]

  An assay is asked for one Attempt at a time: the Bookends, and every Bridge
  written between them, read together and answered once (ADR-0010). A table of
  four is one request rather than six, and the reveal it feeds is one number
  rather than six.
  """

  require Logger

  @typedoc "The Bookends, and every Bridge written between them, in roster order."
  @type request :: %{bookends: [String.t()], bridges: [String.t()]}

  @typedoc """
  Which model answered, at what prompt version, how long it took and what it
  cost — and, because every Attempt is graded in both orderings, what each
  ordering said. Every verdict carries it and the Chronicle writes it down, so that the
  model policy is measured rather than remembered and a grade that looks wrong
  can be argued with in detail.
  """
  @type meta :: %{
          optional(:precedent_hit) => boolean(),
          model: String.t(),
          prompt_version: String.t(),
          cost_usd: float() | nil,
          latency_ms: non_neg_integer(),
          forward: integer(),
          reverse: integer(),
          reasoning_reverse: String.t()
        }

  @typedoc """
  A grade on the ladder's scale, the sentence the players argue with, the line
  the reveal is funny with — written about the words they actually wrote
  (ADR-0005) — and the two of those words that landed furthest apart, which are
  the next Attempt's Bookends.
  """
  @type verdict :: %{
          closeness: integer(),
          reasoning: String.t(),
          quip: String.t(),
          furthest: [String.t()],
          meta: meta()
        }

  @typedoc """
  A closed Page written back to the players in their own words, the line that
  reaches back to an earlier Page (or nothing, on an evening with nothing behind
  it), and what writing it took.
  """
  @type recap :: %{
          recap: String.t(),
          callback: String.t() | nil,
          meta: %{
            model: String.t(),
            prompt_version: String.t(),
            cost_usd: float() | nil,
            latency_ms: non_neg_integer(),
            attempts: pos_integer()
          }
        }

  @callback assay(request()) :: {:ok, verdict()} | {:error, term()}
  @callback author(map() | list(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback recap(map(), String.t()) :: {:ok, recap()} | {:error, term()}
  @callback forge(map() | String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback rank([binary() | map()], map() | String.t()) :: {:ok, [map()]} | {:error, term()}
  @callback name_room([String.t()], [String.t()]) ::
              {:ok, %{word: String.t(), quip: String.t() | nil}} | {:error, term()}
  @callback quip_code(String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  @callback speak(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback score([String.t() | map()], keyword()) :: {:ok, map()} | {:error, term()}

  @doc """
  Scores one Page from its Gives, answering a local file and meta.

  Measured here so latency provenance is kept by the seam.
  """
  @spec score([String.t() | map()], keyword()) :: {:ok, map()} | {:error, term()}
  def score(gives, opts \\ []) do
    gives = Enum.map(gives, &MeaningGame.Steward.Author.give_text/1)
    started = System.monotonic_time(:millisecond)

    case adapter().score(gives, opts) do
      {:ok, %{meta: meta} = answer} ->
        latency = System.monotonic_time(:millisecond) - started
        {:ok, %{answer | meta: Map.put_new(meta, :latency_ms, latency)}}

      {:ok, answer} ->
        latency = System.monotonic_time(:millisecond) - started
        {:ok, Map.put(answer, :meta, %{latency_ms: latency})}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Builds failure provenance for a Foley score failure.
  """
  @spec score_failure(term()) :: map()
  def score_failure(reason) do
    %{
      cost_usd: 0.0,
      failure: if(is_binary(reason), do: reason, else: inspect(reason))
    }
  end

  @doc """
  Builds failure provenance for a Foley voice failure.
  """
  @spec voice_failure(term()) :: map()
  def voice_failure(reason) do
    {provider, voice} = voice_provenance()

    %{
      "provider" => provider,
      "voice" => voice,
      "cost_usd" => 0.0,
      "failure" => format_voice_error(reason)
    }
  end

  defp voice_provenance do
    if adapter() == MeaningGame.Steward.Fake do
      {"fake", "fake-voice"}
    else
      role =
        try do
          role(:foley, :voice)
        rescue
          _ -> %{}
        end

      provider =
        case role[:provider] do
          MeaningGame.Steward.Hume ->
            "hume"

          MeaningGame.Steward.ElevenLabs ->
            "eleven_labs"

          mod when is_atom(mod) and not is_nil(mod) ->
            mod |> Module.split() |> List.last() |> Macro.underscore()

          other ->
            to_string(other || "hume")
        end

      voice = to_string(role[:voice_id] || role[:voice] || "default")
      {provider, voice}
    end
  end

  defp format_voice_error(%RuntimeError{message: msg}), do: msg
  defp format_voice_error({:exit, reason}), do: "process exited: #{inspect(reason)}"
  defp format_voice_error(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_voice_error(reason) when is_binary(reason), do: reason
  defp format_voice_error(reason), do: inspect(reason)

  @doc """
  Generates N candidate sound effects or music tracks for a brief.

  Used only by the forge task.
  """
  @spec forge(map() | String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def forge(brief, opts \\ []) do
    adapter().forge(brief, opts)
  end

  @doc """
  Ranks N candidate audio clips against a brief with one sentence each.

  Used only by the forge task.
  """
  @spec rank([binary() | map()], map() | String.t()) :: {:ok, [map()]} | {:error, term()}
  def rank(candidates, brief) do
    adapter().rank(candidates, brief)
  end

  @doc """
  Speaks one line as audio bytes with format and meta.

  Rendered from the configured voice job. Measured here so latency provenance is
  kept by the seam.
  """
  @spec speak(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def speak(line, opts \\ []) do
    started = System.monotonic_time(:millisecond)

    case adapter().speak(line, opts) do
      {:ok, %{meta: meta} = answer} ->
        latency = System.monotonic_time(:millisecond) - started
        {:ok, %{answer | meta: Map.put_new(meta, :latency_ms, latency)}}

      {:ok, answer} ->
        latency = System.monotonic_time(:millisecond) - started
        {:ok, Map.put(answer, :meta, %{latency_ms: latency})}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Asks the Scribe to name a Room with one four-letter word that nods to the
  history in `digests` and avoids `taken_codes`, answering both word and quip.
  """
  @spec name_room([String.t()], [String.t()]) ::
          {:ok, %{word: String.t(), quip: String.t() | nil}} | {:error, term()}
  def name_room([], _taken_codes), do: {:error, :no_history}

  def name_room(digests, taken_codes) do
    role = role(:scribe, :naming)

    task =
      Task.Supervisor.async_nolink(MeaningGame.Steward.Tasks, fn ->
        adapter().name_room(digests, taken_codes)
      end)

    case Task.yield(task, role.deadline_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, %{word: _} = result}} -> {:ok, result}
      {:ok, {:ok, word}} when is_binary(word) -> {:ok, %{word: word, quip: nil}}
      {:ok, other} -> other
      {:exit, reason} -> {:error, reason}
      nil -> {:error, :timeout}
    end
  end

  @doc """
  Asks the Scribe for a quip about a Room Code drawn at random, answering one line.
  """
  @spec quip_code(String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def quip_code(code) do
    role = role(:scribe, :naming)

    task =
      Task.Supervisor.async_nolink(MeaningGame.Steward.Tasks, fn ->
        adapter().quip_code(code)
      end)

    case Task.yield(task, role.deadline_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, quip}} -> {:ok, quip}
      {:ok, other} -> other
      {:exit, reason} -> {:error, reason}
      nil -> {:error, :timeout}
    end
  end

  @doc """
  Writes one closed Page back into the Chronicle as prose.


  Asked after a Page closes, from a task nobody is waiting on, which is what
  lets the Scribe have a model that writes well rather than one that answers
  fast. An error is not a crash and not an empty paragraph: the Chronicle simply
  has no recap for that Page, which is a thing the book says out loud.
  """
  @spec recap(map(), String.t()) :: {:ok, recap()} | {:error, term()}
  def recap(page, digest) do
    # Narrowed here rather than in the adapter, because what the Scribe may know
    # about a Page is the seam's rule and not one adapter's good manners: the
    # closeness never crosses (ADR-0006).
    adapter().recap(MeaningGame.Steward.Recap.readable(page), digest)
  end

  @doc """
  Writes two Bookends live from player settings (Gives).
  """
  @spec author(map() | list(), keyword()) :: {:ok, map()} | {:error, term()}
  def author(request, opts \\ []) do
    started = System.monotonic_time(:millisecond)

    case adapter().author(request, opts) do
      {:ok, result} -> {:ok, timed(result, System.monotonic_time(:millisecond) - started)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Grades how close an Attempt's Bridges landed to one another.

  How long it took is measured here rather than by the caller, because the
  provenance of a model call is the seam's business and nothing on the other
  side of it should have to remember to hold a stopwatch.

  An error is not a crash and not a zero: the Room turns it into
  `:verdict_unavailable` and the game admits it has no verdict rather than
  inventing one.
  """
  @spec assay(request()) :: {:ok, verdict()} | {:error, term()}
  def assay(request) do
    started = System.monotonic_time(:millisecond)

    case adapter().assay(request) do
      {:ok, verdict} -> {:ok, timed(verdict, System.monotonic_time(:millisecond) - started)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Grades an Attempt's Bridges.
  """
  @spec assay(request(), map() | nil, atom() | String.t() | nil) ::
          {:ok, verdict()} | {:error, term()}
  def assay(request, _page, _arm) do
    assay(request)
  end

  @doc """
  Assigns experiment arm for a Page, strictly alternating arms within the room (:flash then :astra).
  Records the assignment blind in the experiment tables.
  """
  @spec assign_arm(Ecto.UUID.t() | String.t(), map() | String.t() | integer() | nil) ::
          :flash | :astra
  def assign_arm(room_id, page) do
    past_assignments = MeaningGame.Chronicle.experiment_assignments(room_id, "author_model")
    past_arms = Enum.map(past_assignments, & &1.arm)
    arm = MeaningGame.Experiments.assign_arm(past_arms)

    page_identifier =
      cond do
        is_map(page) ->
          page[:id] || page["id"] || page[:number] || "page-#{length(past_arms) + 1}"

        is_binary(page) or is_integer(page) ->
          to_string(page)

        true ->
          "page-#{length(past_arms) + 1}"
      end

    _ =
      MeaningGame.Chronicle.record_experiment_assignment(room_id, %{
        page_identifier: to_string(page_identifier),
        experiment_id: "author_model",
        arm: to_string(arm),
        chapter: "table",
        assigned_at: DateTime.utc_now()
      })

    arm
  rescue
    _ -> :flash
  end

  @doc """
  Rewrites the precedent for these Bridges with the players' ruling.

  A joint player overrule is the only thing in the system that rewrites
  precedent (ADR-0006, design law 3).
  """
  @spec overrule(request(), map()) :: {:ok, term()} | {:error, term()}
  @spec overrule([String.t()], [String.t()], map()) :: {:ok, term()} | {:error, term()}
  def overrule(%{bookends: bookends, bridges: bridges}, ruling) do
    overrule(bookends, bridges, ruling)
  end

  def overrule(bookends, bridges, ruling) when is_list(bookends) and is_list(bridges) do
    role = role(:assayer)
    prompt_version = Map.get(role, :prompt_version, MeaningGame.Steward.Assay.version())

    MeaningGame.Steward.Precedent.overrule(role.model, prompt_version, bookends, bridges, ruling)
  end

  @doc """
  What answers one role: which provider, which model, at what effort, how many
  identical requests, and how long to wait.

  Per-role rather than per-call, because "the Assayer is Gemini 3.8 Flash at low
  effort" is a decision with an ADR behind it (ADR-0005) and not something a
  caller should be able to differ about.
  """
  @spec role(atom()) :: map()
  def role(name) do
    name |> settings() |> Keyword.delete(:jobs) |> Map.new()
  end

  @doc """
  What answers one *job* of one role.

  Only the Scribe has these, and it has them because its two jobs disagree about
  what matters. Naming a Room happens with a table waiting for a Code and wants
  the fast tier; writing a recap happens after everyone has gone to bed and
  wants the model that writes best. A role whose every job wants the same model
  needs none of this and does not have any.

  A job inherits everything the role says and overrides only what it names, so
  the API key and the retry count are written once.
  """
  @spec role(atom(), atom()) :: map()
  def role(name, job) do
    settings = settings(name)

    settings
    |> Keyword.get(:jobs, [])
    |> Keyword.fetch!(job)
    |> then(&Keyword.merge(Keyword.delete(settings, :jobs), &1))
    |> Map.new()
  end

  defp settings(name) do
    :meaning_game
    |> Application.fetch_env!(:steward)
    |> Keyword.fetch!(:roles)
    |> Keyword.fetch!(name)
  end

  @doc """
  Warns at application boot if keys for Foley's active jobs are missing.

  - Music (`:music`): missing `MUREKA_API_KEY` warns that every Page will have
    only the house loop.
  - Voice (`:voice`): missing key(s) for the configured voice provider (`HUME_API_KEY`
    and `HUME_SECRET_KEY` today, `ELEVENLABS_API_KEY` if switched) warns that
    the voice switch will do nothing.

  Emits one warning per Foley job that has no key, in the same words as `bin/deploy`,
  and silence when every key is present.
  """
  @spec warn_missing_foley_keys() :: :ok
  def warn_missing_foley_keys do
    warn_missing_music_key()
    warn_missing_voice_keys()
    :ok
  end

  defp warn_missing_music_key do
    music = role(:foley, :music)

    if missing_key?(music[:api_key]) do
      Logger.warning("no MUREKA_API_KEY — every Page will have only the house loop")
    end
  end

  defp warn_missing_voice_keys do
    voice = role(:foley, :voice)

    missing =
      case voice[:provider] do
        MeaningGame.Steward.ElevenLabs ->
          if missing_key?(voice[:api_key]) and missing_key?(voice[:elevenlabs_api_key]) do
            ["ELEVENLABS_API_KEY"]
          else
            []
          end

        MeaningGame.Steward.Hume ->
          [
            if(missing_key?(voice[:api_key]) and missing_key?(voice[:hume_api_key]),
              do: "HUME_API_KEY"
            ),
            if(missing_key?(voice[:secret_key]) and missing_key?(voice[:hume_secret_key]),
              do: "HUME_SECRET_KEY"
            )
          ]
          |> Enum.reject(&is_nil/1)

        _ ->
          []
      end

    case missing do
      [] ->
        :ok

      keys ->
        Logger.warning("no #{Enum.join(keys, " and ")} — the voice switch will do nothing")
    end
  end

  defp missing_key?(val), do: is_nil(val) or val == ""

  @doc """
  The most Seats a Room may hold while the Assayer is grading it live.

  Not a cost: an Attempt is one grading request however many Seats wrote into it
  (ADR-0010). The cap is about the phone — six Bridges is what a reveal can show
  at once — and about how long a list of words one model can be asked to hold one
  opinion about. The rules are written for a list of any length (ADR-0007).
  """
  @spec seat_cap() :: pos_integer()
  def seat_cap do
    :meaning_game |> Application.fetch_env!(:steward) |> Keyword.fetch!(:seat_cap)
  end

  @default_foley_levels [music: 0.5, stings: 1.2, voice: 1.2, duck: 0.15]
  @default_foley_meld_cue_delay_ms 1800

  @doc "Levels configured for Foley buses: music, stings, voice, duck."
  @spec foley_levels() :: keyword()
  def foley_levels do
    case settings(:foley) do
      settings when is_list(settings) ->
        Keyword.get(settings, :levels, @default_foley_levels)

      _ ->
        @default_foley_levels
    end
  end

  @doc "Delay in milliseconds before the victory cue plays after a meld sting."
  @spec foley_meld_cue_delay_ms() :: non_neg_integer()
  def foley_meld_cue_delay_ms do
    case settings(:foley) do
      settings when is_list(settings) ->
        Keyword.get(settings, :meld_cue_delay_ms, @default_foley_meld_cue_delay_ms)

      _ ->
        @default_foley_meld_cue_delay_ms
    end
  end

  @doc """
  Composes a digest of the Chronicle for feeding to models.

  Computed from the event log, never stored (spec, "The Chronicle"). When the
  Chronicle is empty, returns the default starting message.
  """
  defdelegate digest(room_id_or_slug), to: MeaningGame.Chronicle

  defp timed(verdict, latency_ms) do
    Map.update(verdict, :meta, %{latency_ms: latency_ms}, &Map.put(&1, :latency_ms, latency_ms))
  end

  defp adapter do
    :meaning_game |> Application.fetch_env!(:steward) |> Keyword.fetch!(:adapter)
  end
end
