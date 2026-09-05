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

  An assay is asked for one Attempt at a time: the Anchors, and every Bridge
  written between them, read together and answered once (ADR-0010). A table of
  four is one request rather than six, and the reveal it feeds is one number
  rather than six.
  """

  @typedoc "The Anchors, and every Bridge written between them, in roster order."
  @type request :: %{anchors: [String.t()], bridges: [String.t()]}

  @typedoc """
  Which model answered, at what prompt version, how long it took and what it
  cost — and, because every Attempt is graded in both orderings, what each
  ordering said. Every verdict carries it and the Chronicle writes it down, so that the
  model policy is measured rather than remembered and a grade that looks wrong
  can be argued with in detail.
  """
  @type meta :: %{
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
  the next Attempt's Anchors.
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
  @callback author(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback recap(map(), String.t()) :: {:ok, recap()} | {:error, term()}
  @callback forge(map() | String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback rank([binary() | map()], map() | String.t()) :: {:ok, [map()]} | {:error, term()}

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
  Pre-generates a Page ahead of play against a named Chapter.
  """
  @spec author(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def author(chapter, opts \\ []) do
    adapter().author(chapter, opts)
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
  Grades an Attempt's Bridges and applies experimental arm grading rules.

  A/B variant grading lives behind the Steward seam (CONTEXT.md).
  """
  @spec assay(request(), map() | nil, atom() | String.t() | nil) ::
          {:ok, verdict()} | {:error, term()}
  def assay(request, page, arm) do
    case assay(request) do
      {:ok, verdict} ->
        bridges = request.bridges || []

        graded =
          MeaningGame.Experiments.apply_arm_closeness(verdict, page, arm || :plain, bridges)

        {:ok, graded}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Assigns and records an experiment arm for a Page at Page start.

  Stratified by Chapter so no single arm collects all easy meaning-spaces.
  A/B assignment lives behind the Steward seam (CONTEXT.md).
  """
  @spec assign_arm(Ecto.UUID.t() | String.t(), map() | nil) :: :bait | :plain
  def assign_arm(_room_id, nil), do: :bait

  def assign_arm(room_id, page) do
    chapter = page[:chapter] || page["chapter"] || "default"
    page_id = page[:id] || page["id"] || "unknown"

    past_arms = MeaningGame.Chronicle.chapter_assignments(room_id, chapter, "bait_against_plain")
    arm = MeaningGame.Experiments.assign_arm(past_arms)

    _ =
      MeaningGame.Chronicle.record_experiment_assignment(room_id, %{
        page_identifier: to_string(page_id),
        experiment_id: "bait_against_plain",
        arm: to_string(arm),
        chapter: chapter,
        assigned_at: DateTime.utc_now()
      })

    arm
  end

  @doc """
  Rewrites the precedent for these Bridges with the players' ruling.

  A joint player overrule is the only thing in the system that rewrites
  precedent (ADR-0006, design law 3).
  """
  @spec overrule([String.t()], [String.t()], map()) ::
          {:ok, term()} | {:error, term()}
  def overrule(anchors, bridges, ruling) do
    role = role(:assayer)
    prompt_version = Map.get(role, :prompt_version, MeaningGame.Steward.Assay.version())

    MeaningGame.Steward.Precedent.overrule(role.model, prompt_version, anchors, bridges, ruling)
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
