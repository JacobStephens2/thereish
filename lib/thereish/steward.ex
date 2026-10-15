defmodule Thereish.Steward do
  @moduledoc """
  The one seam through which the game asks models to write, grade and make media.

  The Author, Assayer, Scribe, Foley and Limner use this interface for Bookends,
  verdicts, Recaps, naming, music, voice, effects and images. Callers ask for
  those jobs through `Thereish.Steward`. The Steward owns shared policies such
  as precedent caching, grading both orderings and title fallbacks; the adapters
  and their supporting modules handle provider calls and schema validation.

  `Thereish.Steward.Live` routes work to the configured providers.
  `Thereish.Steward.Fake` supplies controllable responses for tests, including
  delays and failures, without making provider calls.

  Which adapter is in use is configuration, so a test and the couch differ by a
  setting rather than by a code path:

      config :thereish, :steward, adapter: Thereish.Steward.Fake

  So is what each role is answered by. Swapping the Assayer for another model,
  another effort, or another company is `config/config.exs` and nothing else
  (spec, "Operating it"):

      config :thereish, :steward,
        roles: [assayer: [provider: ..., model: ..., effort: ...]]

  An assay is asked for one Attempt at a time: the Bookends and every Bridge
  written between them, read together as one set (ADR-0010). A table of four
  gets one Verdict rather than six pairwise Verdicts. The Steward handles
  precedent caching and both orderings behind that single assay call; the
  live adapter hedges provider requests for each ordering.

  ## In front of the seam

  The rules the game depends on whichever adapter is answering sit here, in
  front of the seam, and the adapters answer only the provider act: a grade, a
  Quip, a title.

  - **The Precedent.** The grade shown is the precedent (ADR-0006). `assay/2`
    reads `Thereish.Steward.Precedent` before asking the adapter, and writes the
    adapter's grade down on a miss. A hit is the cached grade with a fresh Quip
    from the adapter's `quip/1`, or the cached Quip if the fresh one fails or is
    late. `overrule/2` writes the table's ruling under the same key, in one
    transaction with the Chronicle's overrule row.
  - **Both orderings.** Which Bridge is listed first changes a model's answer,
    and how much tracks the model's tier (design law 12): the Steward prototype
    caught an 85-point swing on one pair from reversing the players. So on a
    miss `assay/2` asks the adapter to grade the Bridges in roster order and in
    its reverse, at once, and the grade is the mean of the two. The Assayer's
    `deadline_ms` bounds the pair together. Two orderings and not more: four
    Bridges have twenty-four orderings, and roster order against its reverse is
    the same correction at four that it is at two (ADR-0010).
  - **The title fallback.** A Track always gets a title. When the adapter's
    `title_track/2` answers an error, `title_track/2` answers the title made
    from the Gives.
  """

  require Logger

  alias Thereish.Chronicle
  alias Thereish.Repo
  alias Thereish.Steward.Assay
  alias Thereish.Steward.Digest
  alias Thereish.Steward.Precedent
  alias Thereish.Steward.Title

  @typedoc """
  The Bookends, and every Bridge written between them, in roster order.

  The Game also sends this Page's earlier Attempts, each with its Quip.
  `prior_quips` is composed by `assay/2` and replaces any the caller passed.
  """
  @type request :: %{
          optional(:earlier_attempts) => [map()],
          optional(:prior_quips) => [String.t()],
          optional(atom()) => term(),
          bookends: [String.t()],
          bridges: [String.t()]
        }

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
  An Attempt's Bridges in the order they are shown to the model: roster order
  (`Thereish.Steward.Assay.ordering/1`) or its reverse. Each is a Bridge, bare
  or with the name of the Seat that wrote it.
  """
  @type ordering :: [String.t() | map()]

  @typedoc """
  What an adapter answers for one ordering of an Attempt's Bridges: that
  ordering's Closeness, its words, the two Bridges it names furthest apart, and
  which model answered at what cost. `assay/2` asks for two of these and
  reconciles them into one `t:verdict/0`.
  """
  @type graded_ordering :: %{
          closeness: integer(),
          reasoning: String.t(),
          quip: String.t(),
          furthest: [String.t()],
          model: String.t(),
          cost_usd: number()
        }

  @typedoc """
  A fresh Quip for a Precedent hit, and what writing it cost.
  """
  @type quip :: %{quip: String.t(), meta: %{cost_usd: number() | nil}}

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

  @callback assay(request(), ordering()) :: {:ok, graded_ordering()} | {:error, term()}
  @callback quip(request()) :: {:ok, quip()} | {:error, term()}
  @callback author(map() | list(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback recap(map(), String.t()) :: {:ok, recap()} | {:error, term()}
  @callback forge(map() | String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  @callback rank([binary() | map()], map() | String.t()) :: {:ok, [map()]} | {:error, term()}
  @callback name_room([String.t()], [String.t()]) ::
              {:ok, %{word: String.t(), quip: String.t() | nil}} | {:error, term()}
  @callback quip_code(String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  @callback speak(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback score([String.t() | map()], keyword()) :: {:ok, map()} | {:error, term()}
  @callback vamp([String.t() | map()], keyword()) :: {:ok, map()} | {:error, term()}
  @callback title_track([String.t() | map()], keyword()) :: {:ok, map()} | {:error, term()}
  @callback draw(String.t() | map(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}

  @doc """
  Titles one instrumental Track from its Gives, answering %{title: title, meta: meta}.

  Measured here so latency provenance is kept by the seam. A Track always gets a
  title: when the Scribe cannot write one, whichever adapter is answering, the
  title is the one made from the Gives.
  """
  @spec title_track([String.t() | map()], keyword()) :: {:ok, map()} | {:error, term()}
  def title_track(gives, opts \\ []) do
    gives = Enum.map(gives, &Thereish.Steward.Author.give_text/1)

    measure_call(fn ->
      case adapter().title_track(gives, opts) do
        {:ok, answer} -> {:ok, answer}
        {:error, reason} -> {:ok, fallback_title(gives, reason)}
      end
    end)
  end

  defp fallback_title(gives, reason) do
    Logger.warning("Scribe title failed (#{inspect(reason)}), falling back")

    %{
      title: Title.fallback(gives),
      meta: %{
        model: role(:scribe, :title).model,
        cost_usd: 0.0,
        attempts: 1,
        fallback: true
      }
    }
  end

  @doc """
  Scores one Page from its Gives, answering a local file and meta.

  Measured here so latency provenance is kept by the seam.
  """
  @spec score([String.t() | map()], keyword()) :: {:ok, map()} | {:error, term()}
  def score(gives, opts \\ []) do
    gives = Enum.map(gives, &Thereish.Steward.Author.give_text/1)
    measure_call(fn -> adapter().score(gives, opts) end)
  end

  @doc """
  Vamps one Page from its Gives, answering a short looping instrumental and meta.

  Measured here so latency provenance is kept by the seam.
  """
  @spec vamp([String.t() | map()], keyword()) :: {:ok, map()} | {:error, term()}
  def vamp(gives, opts \\ []) do
    gives = Enum.map(gives, &Thereish.Steward.Author.give_text/1)
    measure_call(fn -> adapter().vamp(gives, opts) end)
  end

  @doc """
  Draws one Mask from a Give and a Seat's colour, answering the image bytes, the
  stored URL and meta.

  The bytes are kept for the Limner bake-off, which judges the pictures
  themselves. A Room draws through `Thereish.Mask.draw/2`, which keeps only the
  URL and meta.

  Measured here so latency provenance is kept by the seam. A vendor that refuses
  a dark Give answers `{:error, :refused}` rather than crashing.
  """
  @spec draw(String.t() | map(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def draw(give, colour, opts \\ []) do
    give = Thereish.Steward.Author.give_text(give)
    retry? = Keyword.get(opts, :retry, true)

    measure_call(fn ->
      res =
        case adapter().draw(give, colour, opts) do
          {:ok, result} ->
            {:ok, result}

          {:error, _reason} when retry? ->
            softened_opts = Keyword.merge(opts, retry: false, softened: true)
            adapter().draw(give, colour, softened_opts)

          {:error, reason} ->
            {:error, reason}
        end

      case res do
        {:ok, %{bytes: bytes} = answer} when not is_map_key(answer, :url) ->
          stored = Thereish.Steward.Limner.store_mask(bytes)
          {:ok, Map.merge(answer, stored)}

        other ->
          other
      end
    end)
  end

  defp measure_call(fun) do
    started = System.monotonic_time(:millisecond)

    case fun.() do
      {:ok, %{meta: meta} = answer} ->
        latency = System.monotonic_time(:millisecond) - started
        {:ok, %{answer | meta: Map.put_new(meta, :latency_ms, latency)}}

      {:ok, answer} when is_map(answer) ->
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
    {provider, model} = music_provenance()

    failure =
      cond do
        is_binary(reason) -> reason
        is_atom(reason) -> Atom.to_string(reason)
        true -> inspect(reason)
      end

    %{
      provider: provider,
      model: model,
      cost_usd: 0.0,
      failure: failure
    }
  end

  defp music_provenance do
    if adapter() == Thereish.Steward.Fake do
      {"fake", "fake-music"}
    else
      %{name: name, settings: settings} = provider(:foley, :music)
      {name, to_string(settings[:model] || "auto")}
    end
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
    if adapter() == Thereish.Steward.Fake do
      {"fake", "fake-voice"}
    else
      %{name: name, settings: settings} = provider(:foley, :voice)
      {name, to_string(settings[:voice_id] || settings[:voice] || "default")}
    end
  end

  defp format_voice_error(%RuntimeError{message: msg}), do: msg
  defp format_voice_error({:exit, reason}), do: "process exited: #{inspect(reason)}"
  defp format_voice_error(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_voice_error(reason) when is_binary(reason), do: reason
  defp format_voice_error(reason), do: inspect(reason)

  @doc """
  Says why the Author could not write, in the words the Game shows the players.
  """
  @spec author_failure(term()) :: String.t()
  def author_failure({:max_tokens, _}), do: "too broad or complex"
  def author_failure(:refused), do: "content declined"
  def author_failure({:refusal, msg}), do: "declined: #{msg}"
  def author_failure(%Req.TransportError{reason: :timeout}), do: "timed out"
  def author_failure(%{reason: :timeout}), do: "timed out"
  def author_failure(:timeout), do: "timed out"
  def author_failure(:unavailable), do: "unavailable"
  def author_failure({:exit, _}), do: "process exited"
  def author_failure(%RuntimeError{message: msg}), do: msg
  def author_failure(reason) when is_binary(reason), do: reason
  def author_failure(reason) when is_atom(reason), do: to_string(reason)
  def author_failure(reason), do: inspect(reason)

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
  Chronicles in `chronicles` and avoids `taken_codes`, answering both word and
  quip.

  `chronicles` holds one Chronicle per earlier Room, as its Page views, oldest
  Page first. A Room with no Pages has nothing to nod to and is left out; when
  none has any, the answer is `{:error, :no_history}`. Each Chronicle is read
  the way the Author reads it (`Thereish.Steward.Digest.author/1`).
  """
  @spec name_room([[map()]], [String.t()]) ::
          {:ok, %{word: String.t(), quip: String.t() | nil}} | {:error, term()}
  def name_room(chronicles, taken_codes) do
    case Enum.reject(chronicles, &(&1 == [])) do
      [] -> {:error, :no_history}
      chronicles -> name_from(Enum.map(chronicles, &Digest.author/1), taken_codes)
    end
  end

  defp name_from(digests, taken_codes) do
    role = role(:scribe, :naming)

    case await_task(role, fn -> adapter().name_room(digests, taken_codes) end) do
      {:ok, %{word: _} = result} -> {:ok, result}
      {:ok, word} when is_binary(word) -> {:ok, %{word: word, quip: nil}}
      other -> other
    end
  end

  @doc """
  Asks the Scribe for a quip about a Room Code drawn at random, answering one line.
  """
  @spec quip_code(String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def quip_code(code) do
    role = role(:scribe, :naming)
    await_task(role, fn -> adapter().quip_code(code) end)
  end

  @doc """
  Runs `call` under the Steward's task supervisor and sends the caller
  `to_message.(answer)` exactly once, for the calls nobody waits on.

  The answer is whatever `call` returned. A call that raises answers
  `{:error, exception}`, and one that exits or throws answers
  `{:error, {kind, reason}}`, so a crash reaches the caller as a failure it has
  a rule for rather than as silence. `to_message` runs outside that guard, so it
  must answer a message for every answer.
  """
  @spec answer_later((-> term()), (term() -> term())) :: DynamicSupervisor.on_start_child()
  def answer_later(call, to_message) do
    caller = self()

    Task.Supervisor.start_child(Thereish.Steward.Tasks, fn ->
      send(caller, to_message.(answer(call)))
    end)
  end

  defp answer(call) do
    call.()
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp await_task(role, fun) do
    task = Task.Supervisor.async_nolink(Thereish.Steward.Tasks, fun)

    case Task.yield(task, role.deadline_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
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

  `page` is the closed Page's view and `earlier` the views of every Page the
  Room played before it, oldest first.
  """
  @spec recap(map(), [map()]) :: {:ok, recap()} | {:error, term()}
  def recap(page, earlier) do
    # Narrowed here rather than in the adapter, because what the Scribe may know
    # about a Page is the seam's rule and not one adapter's good manners: the
    # closeness never crosses (ADR-0006), neither tonight's nor any earlier one.
    adapter().recap(Thereish.Steward.Recap.readable(page), Digest.scribe(earlier))
  end

  @doc """
  Writes Bookends live from player settings (Gives).

  The request carries the count of Bookends wanted — one per Give at a Full
  table, or two — alongside the Gives.

  The Room's Page views, oldest first, ride in as the `chronicle:` option. The
  adapter is handed the Author's digest of them under `digest:`
  (`Thereish.Steward.Digest.author/1`), so a Room with no Pages, or no
  `chronicle:` at all, reads as the first Page. A `digest:` the caller passes is
  replaced: what the Author reads is composed here and nowhere else.
  """
  @spec author(map() | list(), keyword()) :: {:ok, map()} | {:error, term()}
  def author(request, opts \\ []) do
    started = System.monotonic_time(:millisecond)

    {chronicle, opts} = Keyword.pop(opts, :chronicle, [])
    opts = Keyword.put(opts, :digest, Digest.author(chronicle))

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

  On a Precedent miss both orderings are graded and reconciled here. Either
  ordering that errors, crashes, or is still running at the Assayer's
  `deadline_ms` makes the assay `{:error, _}` (`{:error, :timeout}` for the
  deadline). An error is not a crash and not a zero: the Room turns it into
  `:verdict_unavailable` and the game admits it has no verdict rather than
  inventing one.

  The Room's Page views, oldest first, ride in as the `chronicle:` option, as
  they do for `author/2`. The adapter is handed the Assayer's reading of them
  and of the request's earlier Attempts as `prior_quips`
  (`Thereish.Steward.Digest.assayer/2`), so a request with no `chronicle:`
  reads as a Room with no Pages. A `prior_quips` the caller passes is replaced.
  They are set before the Precedent is read, because a hit still asks the
  adapter for a fresh Quip, and that Quip needs them too.
  """
  @spec assay(request(), keyword()) :: {:ok, verdict()} | {:error, term()}
  def assay(request, opts \\ []) do
    started = System.monotonic_time(:millisecond)

    chronicle = Keyword.get(opts, :chronicle, [])
    request = Map.put(request, :prior_quips, Digest.assayer(chronicle, request))

    case precedent_or_graded(request) do
      {:ok, verdict} -> {:ok, timed(verdict, System.monotonic_time(:millisecond) - started)}
      {:error, reason} -> {:error, reason}
    end
  end

  # The grade the players are shown is the precedent (ADR-0006), whichever
  # adapter is answering, so the Precedent is read and written here rather than
  # inside one of them. A miss is graded by the adapter and written down; a hit
  # is the cached grade with a fresh Quip.
  defp precedent_or_graded(request) do
    {model, prompt_version} = precedent_key()

    case Precedent.get(model, prompt_version, request) do
      {:ok, cached} ->
        {:ok, fresh_quip_or_cached(request, cached)}

      :miss ->
        with {:ok, verdict} <- graded(request, prompt_version) do
          Precedent.put(model, prompt_version, request, verdict)
          {:ok, verdict}
        end
    end
  end

  # Both orderings at once, under the Steward's task supervisor so that an
  # adapter that crashes is a grade that failed rather than an exit in the Room.
  # The deadline is the whole grading's budget, both orderings, retries and all,
  # and an ordering still running when it passes is taken down rather than left
  # running, because a request nobody is waiting for is still a request somebody
  # is being billed for.
  defp graded(request, prompt_version) do
    forward = Assay.ordering(request)

    [forward, reverse] =
      [forward, Enum.reverse(forward)]
      |> Enum.map(fn ordering ->
        Task.Supervisor.async_nolink(Thereish.Steward.Tasks, fn ->
          adapter().assay(request, ordering)
        end)
      end)
      |> Task.yield_many(timeout: role(:assayer).deadline_ms, on_timeout: :kill_task)
      |> Enum.map(fn
        {_task, {:ok, answer}} -> answer
        {_task, {:exit, reason}} -> {:error, {:exit, reason}}
        {_task, nil} -> {:error, :timeout}
      end)

    # A missing ordering is no Verdict, never half of one. When both fail, the
    # forward ordering's reason is the one reported.
    with {:ok, forward} <- forward, {:ok, reverse} <- reverse do
      {:ok, reconciled(forward, reverse, prompt_version)}
    end
  end

  # The grade is the mean of the two orderings and the words are the forward
  # one's, because one reveal shows one sentence, one joke and one carry-forward.
  # The furthest pair is the forward ordering's for the same reason the reasoning
  # is: the two orderings can name different pairs, and the next Attempt's Bookends
  # have to be one pair rather than an average of two. The reverse ordering's own
  # grade and reasoning are kept beside them rather than thrown away: when the
  # players argue with a grade, the two arguments the model made are the evidence.
  #
  # The cost is both orderings' answers, retries included — and not the hedged
  # requests that lost, whose usage nobody waited around to hear.
  defp reconciled(forward, reverse, prompt_version) do
    %{
      closeness: round((forward.closeness + reverse.closeness) / 2),
      reasoning: forward.reasoning,
      quip: forward.quip,
      furthest: forward.furthest,
      meta: %{
        model: forward.model,
        prompt_version: prompt_version,
        cost_usd: forward.cost_usd + reverse.cost_usd,
        forward: forward.closeness,
        reverse: reverse.closeness,
        reasoning_reverse: reverse.reasoning
      }
    }
  end

  # The fresh Quip is a provider act, so the adapter writes it; whether the
  # players hear it or the cached one is the Steward's call. It has to land
  # inside the reveal's beat, so a Quip that errors, crashes or is late is the
  # cached one, which cost nothing.
  defp fresh_quip_or_cached(request, cached) do
    role = role(:assayer)
    timeout = min(Map.get(role, :quip_timeout_ms, 2_000), Map.get(role, :timeout_ms, 2_000))
    task = Task.Supervisor.async_nolink(Thereish.Steward.Tasks, fn -> adapter().quip(request) end)

    {quip, cost_usd} =
      case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, {:ok, %{quip: quip, meta: meta}}} -> {quip, meta.cost_usd}
        _fallback -> {cached.quip, 0.0}
      end

    %{
      cached
      | quip: quip,
        meta: Map.merge(cached.meta, %{precedent_hit: true, cost_usd: cost_usd})
    }
  end

  # The one place the Precedent's key is made, because an overrule written
  # under a key the assay never reads would be a ruling nobody is shown.
  defp precedent_key do
    role = role(:assayer)
    {role.model, Map.get(role, :prompt_version, Assay.version())}
  end

  @doc """
  Assigns the next Page in a Room its Assignment. A/B assignment
  lives behind the Steward; `Thereish.Experiments` keeps the rows.
  """
  @spec assign_arm(Ecto.UUID.t() | String.t()) :: Thereish.Experiments.Assignment.t()
  def assign_arm(room_id), do: Thereish.Experiments.assign(room_id)

  @doc """
  Records the table's agreed overrule: the Chronicle's overrule row, and the
  Precedent rewritten with the table's ruling under the Precedent's key.

  A joint overrule is the only thing in the system that rewrites precedent
  (ADR-0006, design law 3), and the Chronicle must never show one the
  Precedent did not receive, so both writes are one transaction: if either
  fails, neither lands.
  """
  @spec overrule(Ecto.UUID.t(), Thereish.Overrule.ruling()) ::
          {:ok, Thereish.Chronicle.Overrule.t()} | {:error, term()}
  def overrule(room_id, ruling) do
    {model, prompt_version} = precedent_key()

    Repo.transaction(fn ->
      with {:ok, row} <- Chronicle.record_overrule(room_id, ruling),
           {:ok, _precedent} <-
             Precedent.overrule(model, prompt_version, ruling.bookends, ruling.bridges, %{
               closeness: ruling.couple_closeness,
               reasoning: ruling.couple_reasoning,
               quip: ruling.couple_quip
             }) do
        row
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
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

  @doc """
  What answers one media job: the provider module, the name the Chronicle knows
  it by, the job's settings with its credentials resolved, and the environment
  variables still missing.

  The media roles are the Limner and Foley's voice, music, Vamp and effects
  jobs. `module` is `override` when one is given, otherwise the configured
  `provider`; a role that names none is a configuration error, so this raises.
  `name` is the module's last alias, underscored (`hume`, `eleven_labs`).

  Each credential the module declares through `credentials/0` is the job's own
  field (`api_key`) or else the vendor-scoped field on the role
  (`hume_api_key`). An empty string counts as absent, and an absent credential
  is `nil` in `settings` and its environment variable is in `missing`.
  """
  @spec provider(role :: atom(), job :: atom() | nil, override :: module() | nil) :: %{
          module: module(),
          name: String.t(),
          settings: map(),
          missing: [String.t()]
        }
  def provider(role, job \\ nil, override \\ nil) do
    settings = if job, do: role(role, job), else: role(role)

    module =
      override || settings[:provider] ||
        raise ArgumentError,
              "no provider configured for #{inspect(Enum.reject([role, job], &is_nil/1))}"

    provider_name = module |> Module.split() |> List.last() |> Macro.underscore()

    {settings, missing} =
      Enum.reduce(module.credentials(), {settings, []}, fn {field, env}, {settings, missing} ->
        case present(settings[field]) || present(settings[:"#{provider_name}_#{field}"]) do
          nil -> {Map.put(settings, field, nil), [env | missing]}
          key -> {Map.put(settings, field, key), missing}
        end
      end)

    %{module: module, name: provider_name, settings: settings, missing: Enum.reverse(missing)}
  end

  defp present(value) when is_binary(value) and value != "", do: value
  defp present(_value), do: nil

  defp settings(name) do
    :thereish
    |> Application.fetch_env!(:steward)
    |> Keyword.fetch!(:roles)
    |> Keyword.fetch!(name)
  end

  @doc """
  Warns at application boot if keys for Foley's active jobs are missing.

  - Music (`:music`): a missing key (`MUREKA_API_KEY` today) warns that every
    Page will have only the house loop.
  - Voice (`:voice`): missing key(s) for the configured voice provider
    (`HUME_API_KEY` and `HUME_SECRET_KEY` today, `ELEVENLABS_API_KEY` if
    switched) warns that the voice switch will do nothing.

  Emits one warning per Foley job that has no key, in the same words as
  `bin/deploy`, and silence when every key is present. Which keys are missing
  is the resolver's answer (`provider/3`).
  """
  @spec warn_missing_foley_keys() :: :ok
  def warn_missing_foley_keys do
    warn_missing(provider(:foley, :music), "every Page will have only the house loop")
    warn_missing(provider(:foley, :voice), "the voice switch will do nothing")
    :ok
  end

  @doc """
  Warns at application boot if the configured Limner provider has no key.

  Recraft is the house Limner. Without `RECRAFT_AI_API_KEY` (or `api_key` /
  `recraft_api_key` on the role) every Give lands as a colour dot.
  """
  @spec warn_missing_limner_keys() :: :ok
  def warn_missing_limner_keys do
    warn_missing(provider(:limner), "every Seat will wear a colour dot")
    :ok
  end

  defp warn_missing(%{missing: []}, _consequence), do: :ok

  defp warn_missing(%{missing: keys}, consequence) do
    Logger.warning("no #{Enum.join(keys, " and ")} — #{consequence}")
  end

  @doc """
  The most Seats a Room may hold while the Assayer is grading it live.

  Not a cost: an Attempt is one grading request however many Seats wrote into it
  (ADR-0010). The cap is about the phone — eight Bridges is what a reveal can show
  at once — and about how long a list of words one model can be asked to hold one
  opinion about. The rules are written for a list of any length (ADR-0007).
  """
  @spec seat_cap() :: pos_integer()
  def seat_cap do
    :thereish |> Application.fetch_env!(:steward) |> Keyword.fetch!(:seat_cap)
  end

  @default_foley_levels [music: 0.5, stings: 1.2, voice: 1.2, duck: 0.15, duck_stings: 0.35]
  @default_foley_meld_cue_delay_ms 1800

  @doc "Levels configured for Foley buses: music, stings, voice, duck, duck_stings."
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

  defp timed(verdict, latency_ms) do
    Map.update(verdict, :meta, %{latency_ms: latency_ms}, &Map.put(&1, :latency_ms, latency_ms))
  end

  @doc "Returns the configured Steward adapter module (Live or Fake)."
  def adapter do
    :thereish |> Application.fetch_env!(:steward) |> Keyword.fetch!(:adapter)
  end
end
