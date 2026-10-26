defmodule Thereish.Steward.Live do
  @moduledoc """
  The live adapter for the Author, Assayer, Scribe, Foley and Limner.

  It implements `Thereish.Steward` alongside `Thereish.Steward.Fake`, routing
  writing, grading and media jobs to the configured providers through their
  supporting modules. The same interface supplies Bookends, grades, Quips,
  Recaps, naming, music, voice, effects and images in live play and tests.

  The Steward handles precedent caching, asking for both orderings, the
  deadline on the pair and reconciling them into one Verdict in front of this
  adapter. Here the Assayer grades one ordering at a time, the Scribe's Recaps
  pass through Vale, and media jobs use their configured providers and caches.
  The hedging policy below applies to each Assayer ordering.

  ## Hedging, because the tail is the network

  Each ordering is asked as `requests` identical requests to the **same** model
  and the first answer wins. Identical, and one model: racing two different
  models would make the grade a coin toss between two distributions, which is
  the opposite of the consistency the cache exists to protect (design law 11).
  It shortens the tail where the tail is queueing rather than generation, which
  on the fast tier is where the tail is — the prototype measured GLM's P95 total
  falling from 1.52 s to 1.17 s.

  The loser is billed for whatever it produced before it was abandoned, and the
  ordering's `cost_usd` does not include it: nothing waits for a request whose
  answer is not being used, so its usage never comes back to be counted. At
  fast-tier prices that is noise, and the number on the verdict is the cost of
  the grade the players were shown.

  A grading that fails, however it fails, is `{:error, _}` here and
  `:verdict_unavailable` in the Room, and the couple are asked to make the call
  themselves. It is never a number this module made up.

  Every `assay/2` here is a grade asked now. Whether the players are shown it or
  the Precedent is `Thereish.Steward`'s call, made before this module is asked.
  """
  @behaviour Thereish.Steward

  alias Thereish.Steward
  alias Thereish.Steward.Assay
  alias Thereish.Steward.Gate
  alias Thereish.Steward.Music
  alias Thereish.Steward.Naming
  alias Thereish.Steward.Recap
  alias Thereish.Steward.Title
  alias Thereish.Steward.TrackCache
  alias Thereish.Steward.Vale

  @impl true
  def assay(%{bookends: _bookends} = request, ordering) do
    role = Steward.role(:assayer)
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

  # One request and no retry, because a fresh Quip has to land inside the
  # reveal's beat; the Steward decides what to show if it does not.
  @impl true
  def quip(request) do
    role = Steward.role(:assayer) |> Map.merge(%{requests: 1, retries: 0})
    prompt = Assay.quip_prompt(request, Assay.ordering(request))

    case Gate.answer(role, prompt, &Assay.check_quip/1) do
      {:ok, answer} -> {:ok, %{quip: Assay.quip(answer.json), meta: %{cost_usd: answer.cost_usd}}}
      {:error, reason} -> {:error, reason}
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

    count = Thereish.Steward.Author.requested_count(request)
    prompt = Thereish.Steward.Author.prompt(gives, digest, count)

    case Gate.answer(role, prompt, &Thereish.Steward.Author.check(&1, gives, count)) do
      {:ok, answer} ->
        bookends = answer.json["bookends"]
        why = answer.json["why"]

        {:ok,
         %{
           bookends: bookends,
           from: answer.json["from"],
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
        provider = Steward.provider(:foley, :music)
        prompt = Map.get(brief_map, :prompt) || brief_map[:text] || ""

        # Sequential, because Mureka (an alternative provider) allows one request at a time
        results =
          Enum.map(1..n, fn _ ->
            params =
              provider.settings
              |> Map.merge(brief_map)
              |> Map.merge(Map.new(opts))
              |> Map.put(:prompt, prompt)
              |> Map.put(:n, Map.get(provider.settings, :n, 1))

            provider.module.generate(params)
          end)

        wrap_candidates(results, provider, start_time)

      _effects ->
        provider = Steward.provider(:foley, :effects)
        text = Map.get(brief_map, :prompt) || Map.get(brief_map, :text) || ""
        timeout_ms = Map.get(provider.settings, :timeout_ms, 30_000)

        tasks =
          for _ <- 1..n do
            Task.async(fn ->
              params =
                provider.settings
                |> Map.merge(brief_map)
                |> Map.merge(Map.new(opts))
                |> Map.put(:text, text)

              provider.module.generate(params)
            end)
          end

        results = Task.await_many(tasks, timeout_ms * n)
        wrap_candidates(results, provider, start_time)
    end
  end

  defp wrap_candidates(results, provider, start_time) do
    latency_ms = System.monotonic_time(:millisecond) - start_time

    with :ok <- check_all_ok(results) do
      candidates =
        Enum.map(results, fn {:ok, result} ->
          %{
            bytes: result.bytes,
            meta: %{
              provider: provider.name,
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
    {override, opts} = Keyword.pop(opts, :provider)
    provider = Steward.provider(:foley, :voice, override)

    merged_opts =
      provider.settings
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Keyword.merge(opts)

    with {:ok, clip} <- provider.module.speak(line, merged_opts) do
      {:ok,
       Map.update(clip, :meta, %{provider: provider.name}, &Map.put(&1, :provider, provider.name))}
    end
  end

  @impl true
  def score(gives, opts \\ []) do
    case TrackCache.get(gives) do
      {:ok, track} ->
        {:ok, track}

      :miss ->
        provider = Steward.provider(:foley, :music)
        prompt = Music.prompt(gives)

        params =
          provider.settings
          |> Map.merge(Map.new(opts))
          |> Map.put(:prompt, prompt)
          |> Map.put(:n, 1)

        with {:ok, result} <- provider.module.generate(params),
             {:ok, track} <- TrackCache.store(gives, result, provider: provider.name) do
          {:ok, track}
        end
    end
  end

  @impl true
  def vamp(gives, opts \\ []) do
    provider = Steward.provider(:foley, :vamp)
    prompt = Music.vamp_prompt(gives)

    params =
      provider.settings
      |> Map.merge(Map.new(opts))
      |> Map.put(:text, prompt)
      |> Map.put(:duration_seconds, 30.0)
      |> Map.put(:loop, true)

    case provider.module.generate(params) do
      {:ok, %{bytes: bytes} = result} ->
        vamp_dir = Path.join(TrackCache.media_dir(), "vamps")
        File.mkdir_p!(vamp_dir)
        hash = :crypto.hash(:sha256, prompt) |> Base.encode16(case: :lower) |> binary_part(0, 16)
        filename = "vamp-#{hash}.mp3"
        disk_path = Path.join(vamp_dir, filename)
        File.write!(disk_path, bytes)
        web_path = "/media/vamps/#{filename}"

        model = result[:model] || Map.get(provider.settings, :model)
        cost_usd = result[:cost_usd] || 0.0

        {:ok,
         %{
           path: web_path,
           duration: 30,
           format: :mp3,
           loop: true,
           meta: %{
             provider: provider.name,
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
    {override, opts} = Keyword.pop(opts, :provider)
    provider = Steward.provider(:limner, nil, override)

    prompt =
      Keyword.get(opts, :prompt) ||
        if(Keyword.get(opts, :softened, false),
          do: Thereish.Steward.Limner.softened_prompt(give, colour),
          else: Thereish.Steward.Limner.prompt(give, colour)
        )

    references = Thereish.Steward.Limner.references(provider.settings)

    params =
      provider.settings
      |> Map.merge(Map.new(opts))
      |> Map.put(:prompt, prompt)
      |> Map.put(:give, Thereish.Steward.Author.give_text(give))
      |> Map.put(:colour, colour)
      |> Map.put(:references, references)

    case provider.module.generate(params) do
      {:ok, result} ->
        {:ok,
         %{
           bytes: result.bytes,
           format: result[:format] || :png,
           meta: %{
             provider: provider.name,
             model: result.model,
             cost_usd: result.cost_usd
           }
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def title_track(gives, _opts \\ []) do
    role = Steward.role(:scribe, :title)
    prompt = Title.prompt(gives)

    with {:ok, answer} <- Gate.answer(role, prompt, &Title.check/1) do
      {:ok,
       %{
         title: Title.title(answer.json),
         meta: %{
           model: answer.model,
           cost_usd: answer.cost_usd,
           latency_ms: answer.latency_ms,
           attempts: answer.attempts
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
end
