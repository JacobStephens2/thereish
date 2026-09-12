defmodule Thereish.Steward.Live do
  @moduledoc """
  The Assayer with a real model behind it.

  It is one of the two adapters that satisfy `Thereish.Steward`, and the game
  cannot tell it from the other one: the Room asks for an Attempt's Bridges to be
  graded and gets back a closeness, a sentence, the two words furthest apart, and
  a joke. Everything that makes a live grade different from a fake one — a
  provider, two orderings, two identical requests, a validator, a price — is
  spent here and mentioned nowhere else.

  ## Both orderings, because the model has a favourite side

  Which Bridge is listed first changes the answer, and how much it changes it
  tracks the model's tier (design law 12) — the Steward prototype caught an
  85-point swing on one pair from reversing the players. So every Attempt is
  graded twice, in parallel, in roster order and in its reverse, and the number
  the players see is the mean of the two. Both orderings are kept on the verdict,
  along with the reverse ordering's reasoning: a wide gap between them is the
  single most useful thing to know about a grade that looks wrong.

  Two orderings and not more. Four Bridges have twenty-four orderings, and
  grading all of them would be a different experiment with a different budget;
  roster order against its reverse is the same correction at four that it is at
  two (ADR-0010).

  ## Hedging, because the tail is the network

  Each ordering is asked as `requests` identical requests to the **same** model
  and the first answer wins. Identical, and one model: racing two different
  models would make the grade a coin toss between two distributions, which is
  the opposite of the consistency the cache exists to protect (design law 11).
  It shortens the tail where the tail is queueing rather than generation, which
  on the fast tier is where the tail is — the prototype measured GLM's P95 total
  falling from 1.52 s to 1.17 s.

  The loser is billed for whatever it produced before it was abandoned, and the
  verdict's `cost_usd` does not include it: nothing waits for a request whose
  answer is not being used, so its usage never comes back to be counted. At
  fast-tier prices that is noise, and the number on the verdict is the cost of
  the grade the players were shown.

  A grading that fails, however it fails, is `{:error, _}` here and
  `:verdict_unavailable` in the Room, and the couple are asked to make the call
  themselves. It is never a number this module made up.
  """
  @behaviour Thereish.Steward

  require Logger

  alias Thereish.Steward
  alias Thereish.Steward.Assay
  alias Thereish.Steward.Gate
  alias Thereish.Steward.Music
  alias Thereish.Steward.Naming
  alias Thereish.Steward.Precedent
  alias Thereish.Steward.Recap
  alias Thereish.Steward.Title
  alias Thereish.Steward.TrackCache
  alias Thereish.Steward.Vale

  @impl true
  def assay(%{bookends: _bookends} = request) do
    role = Steward.role(:assayer)
    model = role.model
    prompt_version = Map.get(role, :prompt_version, Assay.version())

    case Precedent.get(model, prompt_version, request) do
      {:ok, verdict} ->
        {:ok, fresh_quip_or_fallback(role, request, verdict)}

      :miss ->
        with {:ok, verdict} <- grade_live(role, request, prompt_version) do
          Precedent.put(model, prompt_version, request, verdict)
          {:ok, verdict}
        end
    end
  end

  @impl true
  def author(request, opts \\ []) do
    job = Keyword.get(opts, :job, :flash)

    role =
      try do
        Steward.role(:author, job)
      rescue
        _ -> Steward.role(:author)
      end

    gives =
      cond do
        is_map(request) and is_list(request[:gives]) -> request[:gives]
        is_map(request) and is_list(request["gives"]) -> request["gives"]
        is_list(request) -> request
        true -> []
      end

    digest =
      Keyword.get(opts, :digest) ||
        (is_map(request) && (request[:digest] || request["digest"]))

    count = Thereish.Steward.Author.requested_count(request, opts)
    prompt = Thereish.Steward.Author.prompt(gives, digest, count)

    case Gate.answer(role, prompt, &Thereish.Steward.Author.check(&1, gives, count)) do
      {:ok, answer} ->
        bookends = answer.json["bookends"]
        why = answer.json["why"]

        {:ok,
         %{
           bookends: bookends,
           why: why,
           meta: %{
             model: answer.model,
             arm: job,
             prompt_version: Map.get(role, :prompt_version, Thereish.Steward.Author.version()),
             cost_usd: answer.cost_usd,
             latency_ms: answer.latency_ms,
             attempts: answer.attempts,
             why: why,
             count: count
           }
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def recap(page, digest) do
    role = Steward.role(:scribe, :recap)
    prompt = Recap.prompt(page, digest)

    case Gate.answer(role, prompt, &accept(&1, page)) do
      {:ok, answer} ->
        {:ok,
         Map.put(Recap.recap(answer.json), :meta, %{
           model: answer.model,
           prompt_version: Map.get(role, :prompt_version, Recap.version()),
           cost_usd: answer.cost_usd,
           latency_ms: answer.latency_ms,
           attempts: answer.attempts
         })}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def forge(brief, opts \\ []) do
    brief_map = if is_binary(brief), do: %{prompt: brief}, else: Map.new(brief)
    n = Keyword.get(opts, :n, 4)
    kind = Map.get(brief_map, :kind) || Keyword.get(opts, :kind, :effects)

    start_time = System.monotonic_time(:millisecond)

    case kind do
      :music ->
        role = Steward.role(:foley, :music)
        prompt = Map.get(brief_map, :prompt) || brief_map[:text] || ""

        # Mureka enforces concurrent requests limit 1, so generate sequentially
        results =
          Enum.map(1..n, fn _ ->
            params =
              role
              |> Map.merge(brief_map)
              |> Map.merge(Map.new(opts))
              |> Map.put(:prompt, prompt)
              |> Map.put(:n, Map.get(role, :n, 1))

            Thereish.Steward.Mureka.generate(params)
          end)

        wrap_candidates(results, start_time)

      _effects ->
        role = Steward.role(:foley, :effects)
        text = Map.get(brief_map, :prompt) || Map.get(brief_map, :text) || ""
        timeout_ms = Map.get(role, :timeout_ms, 30_000)

        tasks =
          for _ <- 1..n do
            Task.async(fn ->
              params =
                role
                |> Map.merge(brief_map)
                |> Map.merge(Map.new(opts))
                |> Map.put(:text, text)

              Thereish.Steward.ElevenLabs.generate(params)
            end)
          end

        results = Task.await_many(tasks, timeout_ms * n)
        wrap_candidates(results, start_time)
    end
  end

  defp wrap_candidates(results, start_time) do
    latency_ms = System.monotonic_time(:millisecond) - start_time

    with :ok <- check_all_ok(results) do
      candidates =
        Enum.map(results, fn {:ok, result} ->
          %{
            bytes: result.bytes,
            meta: %{
              model: result.model,
              cost_usd: result.cost_usd,
              latency_ms: latency_ms
            }
          }
        end)

      {:ok, candidates}
    end
  end

  defp check_all_ok(results) do
    case Enum.find(results, fn
           {:ok, _} -> false
           _ -> true
         end) do
      nil -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def rank(candidates, brief) do
    role = Steward.role(:foley, :ear)
    Thereish.Steward.Gemini.rank(candidates, brief, role)
  end

  @impl true
  def speak(line, opts \\ []) do
    role =
      try do
        Steward.role(:foley, :voice)
      rescue
        _ -> %{}
      end

    provider =
      Keyword.get(opts, :provider) ||
        role[:provider] ||
        Thereish.Steward.Hume

    merged_opts =
      role
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Keyword.merge(opts)
      |> Keyword.put(:provider, provider)

    provider.speak(line, merged_opts)
  end

  @impl true
  def score(gives, opts \\ []) do
    case TrackCache.get(gives) do
      {:ok, track} ->
        {:ok, track}

      :miss ->
        role = Steward.role(:foley, :music)
        prompt = Music.prompt(gives)

        params =
          role
          |> Map.merge(Map.new(opts))
          |> Map.put(:prompt, prompt)
          |> Map.put(:n, 1)

        with {:ok, result} <- Thereish.Steward.Mureka.generate(params),
             {:ok, track} <- TrackCache.store(gives, result) do
          {:ok, track}
        end
    end
  end

  @impl true
  def vamp(gives, opts \\ []) do
    role =
      try do
        Steward.role(:foley, :vamp)
      rescue
        _ -> %{}
      end

    prompt = Music.vamp_prompt(gives)

    params =
      role
      |> Map.merge(Map.new(opts))
      |> Map.put(:job_kind, :vamp)
      |> Map.put(:text, prompt)
      |> Map.put(:duration_seconds, 30.0)
      |> Map.put(:loop, true)

    case Thereish.Steward.ElevenLabs.generate(params) do
      {:ok, %{bytes: bytes} = result} ->
        vamp_dir = Path.join(TrackCache.media_dir(), "vamps")
        File.mkdir_p!(vamp_dir)
        hash = :crypto.hash(:sha256, prompt) |> Base.encode16(case: :lower) |> binary_part(0, 16)
        filename = "vamp-#{hash}.mp3"
        disk_path = Path.join(vamp_dir, filename)
        File.write!(disk_path, bytes)
        web_path = "/media/vamps/#{filename}"

        model = result[:model] || Map.get(role, :model, "eleven_text_to_sound_v2")
        cost_usd = result[:cost_usd] || 0.0

        {:ok,
         %{
           path: web_path,
           duration: 30,
           format: :mp3,
           loop: true,
           meta: %{
             provider: "eleven_labs",
             model: model,
             cost_usd: cost_usd,
             duration_seconds: 30.0,
             loop: true
           }
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def name_room([], _taken_codes), do: {:error, :no_history}

  def name_room(digests, taken_codes) do
    role = Steward.role(:scribe, :naming)
    prompt = Naming.prompt(digests, taken_codes)

    case Gate.answer(role, prompt, &Naming.check(&1, taken_codes)) do
      {:ok, answer} ->
        {:ok, %{word: Naming.word(answer.json), quip: Naming.quip(answer.json)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def quip_code(code) do
    role = Steward.role(:scribe, :naming)
    prompt = Naming.quip_prompt(code)

    case Gate.answer(role, prompt, fn _json -> :ok end) do
      {:ok, answer} ->
        {:ok, Naming.quip(answer.json)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def draw(give, colour, opts \\ []) do
    role =
      try do
        Steward.role(:limner)
      rescue
        _ -> %{}
      end

    prompt =
      Keyword.get(opts, :prompt) ||
        if(Keyword.get(opts, :softened, false),
          do: Thereish.Steward.Limner.softened_prompt(give, colour),
          else: Thereish.Steward.Limner.prompt(give, colour)
        )

    references = Thereish.Steward.Limner.references(role)

    provider =
      Keyword.get(opts, :provider) ||
        role[:provider] ||
        Thereish.Steward.Fal

    params =
      role
      |> Map.merge(Map.new(opts))
      |> Map.put(:prompt, prompt)
      |> Map.put(:give, Thereish.Steward.Author.give_text(give))
      |> Map.put(:colour, colour)
      |> Map.put(:references, references)

    case provider.generate(params) do
      {:ok, result} ->
        {:ok,
         %{
           bytes: result.bytes,
           format: result[:format] || :png,
           meta: %{
             provider: provider_name(provider),
             model: result.model,
             cost_usd: result.cost_usd
           }
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp provider_name(mod) when is_atom(mod) do
    mod |> Module.split() |> List.last() |> Macro.underscore()
  end

  @impl true
  def title_track(gives, _opts \\ []) do
    role = Steward.role(:scribe, :title)
    prompt = Title.prompt(gives)

    case Gate.answer(role, prompt, &Title.check/1) do
      {:ok, answer} ->
        title = Title.title(answer.json)

        {:ok,
         %{
           title: title,
           meta: %{
             model: answer.model,
             cost_usd: answer.cost_usd,
             latency_ms: answer.latency_ms,
             attempts: answer.attempts
           }
         }}

      {:error, reason} ->
        Logger.warning("Scribe title failed (#{inspect(reason)}), falling back")

        {:ok,
         %{
           title: Title.fallback(gives),
           meta: %{
             model: role.model,
             cost_usd: 0.0,
             latency_ms: 0,
             attempts: 1,
             fallback: true
           }
         }}
    end
  end

  # The Scribe's gate, both halves of it, run as the Gate's own last word — so
  # the repair pass is the retry the seam already knows how to do and the model
  # is handed the rule that fired rather than a shrug (design law 14). The
  # `retries: 1` on the role is what makes it *one* repair pass.
  #
  # The cheap check runs first: a recap about nobody's words is a rejection a
  # regular expression can write, and there is no sense starting a linter to
  # find it.
  # The two pieces of prose are linted separately, because `Scribe.Length` caps
  # the recap at eighty words and a callback sharing that budget would make the
  # recap shorter for having remembered something.
  defp accept(json, page) do
    with :ok <- Recap.check(json, page) do
      %{recap: recap, callback: callback} = Recap.recap(json)

      with :ok <- Vale.check(recap) do
        if callback, do: Vale.check(callback), else: :ok
      end
    end
  end

  defp grade_live(role, request, prompt_version) do
    items = ordering_items(request)

    [forward, reverse] =
      [items, Enum.reverse(items)]
      |> Enum.map(fn ordering ->
        Task.async(fn -> graded(role, request, ordering) end)
      end)
      # The grading's whole budget: one request's timeout is `timeout_ms`, and
      # this is what all of them together, retries included, may spend before
      # the game is told there is no verdict.
      |> await(role.deadline_ms)

    with {:ok, forward} <- forward, {:ok, reverse} <- reverse do
      {:ok, reconciled(forward, reverse, prompt_version)}
    end
  end

  defp ordering_items(%{seat_bridges: seat_bridges})
       when is_list(seat_bridges) and length(seat_bridges) >= 2 do
    seat_bridges
  end

  defp ordering_items(%{player_bridges: player_bridges})
       when is_list(player_bridges) and length(player_bridges) >= 2 do
    player_bridges
  end

  defp ordering_items(%{bridges: bridges}) when is_list(bridges) do
    bridges
  end

  # An ordering that never came back at all is a verdict the game does not have.
  # The tasks are taken down rather than left running, because a request nobody
  # is waiting for is still a request somebody is being billed for.
  defp await(tasks, timeout) do
    Task.await_many(tasks, timeout)
  catch
    :exit, _reason ->
      Enum.each(tasks, &Task.shutdown(&1, :brutal_kill))

      [{:error, :timeout}, {:error, :timeout}]
  end

  defp graded(role, request, ordering) do
    prompt = Assay.prompt(request, ordering)
    check = &Assay.check(&1, ordering)

    case first_answer(role.requests, fn -> Gate.answer(role, prompt, check) end) do
      {:ok, answer} ->
        {:ok,
         Map.merge(Assay.verdict(answer.json, ordering), Map.take(answer, [:model, :cost_usd]))}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # One request is not a race, and asking for a race of one should not cost a
  # process.
  defp first_answer(requests, ask) when requests <= 1, do: ask.()

  defp first_answer(requests, ask) do
    tasks = for _ <- 1..requests, do: Task.async(ask)
    {answer, losers} = race(tasks, nil)

    Enum.each(losers, &Task.shutdown(&1, :brutal_kill))

    answer
  end

  # First answer wins — unless it is not an answer. A request that came back
  # with an error has not answered anything, and the whole point of having sent
  # a second one is that it might. The first failure is what is reported if
  # every one of them fails.
  defp race([], first_error), do: {first_error || {:error, :no_answer}, []}

  defp race(tasks, first_error) do
    refs = Map.new(tasks, &{&1.ref, &1})

    receive do
      {ref, result} when is_map_key(refs, ref) ->
        Process.demonitor(ref, [:flush])
        rest = List.delete(tasks, Map.fetch!(refs, ref))

        case result do
          {:ok, _answer} -> {result, rest}
          error -> race(rest, first_error || error)
        end

      {:DOWN, ref, :process, _pid, reason} when is_map_key(refs, ref) ->
        rest = List.delete(tasks, Map.fetch!(refs, ref))

        race(rest, first_error || {:error, {:exit, reason}})
    end
  end

  # The grade is the mean of the two orderings and the words are the forward
  # one's, because one reveal shows one sentence, one joke and one carry-forward.
  # The furthest pair is the forward ordering's for the same reason the reasoning
  # is: the two orderings can name different pairs, and the next Attempt's Bookends
  # have to be one pair rather than an average of two. The reverse ordering's own
  # reasoning is kept beside them rather than thrown away: when the players argue
  # with a grade, the two arguments the model made are the evidence.
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

  defp fresh_quip_or_fallback(role, request, cached) do
    ordering = ordering_items(request)
    prompt = Assay.quip_prompt(request, ordering)
    check = &Assay.check_quip/1

    quip_role = Map.merge(role, %{requests: 1, retries: 0})

    timeout =
      min(
        Map.get(quip_role, :quip_timeout_ms, 2_000),
        Map.get(quip_role, :timeout_ms, 2_000)
      )

    start_time = System.monotonic_time(:millisecond)

    task =
      Task.Supervisor.async_nolink(Thereish.Steward.Tasks, fn ->
        Gate.answer(quip_role, prompt, check)
      end)

    {quip, cost_usd} =
      case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, {:ok, answer}} ->
          {Assay.quip(answer.json), answer.cost_usd}

        _fallback ->
          {cached.quip, 0.0}
      end

    latency_ms = System.monotonic_time(:millisecond) - start_time

    %{
      cached
      | quip: quip,
        meta:
          Map.merge(cached.meta, %{
            precedent_hit: true,
            cost_usd: cost_usd,
            latency_ms: latency_ms
          })
    }
  end
end
