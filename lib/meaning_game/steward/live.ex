defmodule MeaningGame.Steward.Live do
  @moduledoc """
  The Assayer with a real model behind it.

  It is one of the two adapters that satisfy `MeaningGame.Steward`, and the game
  cannot tell it from the other one: the Room asks for a pair of Bridges to be
  graded and gets back a closeness, a sentence, and a joke. Everything that
  makes a live grade different from a fake one — a provider, two orderings, two
  identical requests, a validator, a price — is spent here and mentioned nowhere
  else.

  ## Both orderings, because the model has a favourite side

  Which of the two Bridges is listed first changes the answer, and how much it
  changes it tracks the model's tier (design law 12) — the Steward prototype
  caught an 85-point swing on one pair from reversing the players. So every pair
  is graded twice, in parallel, once each way, and the number the players see is
  the mean of the two. Both orderings are kept on the verdict, along with the
  reverse ordering's reasoning: a wide gap between them is the single most useful
  thing to know about a grade that looks wrong.

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
  @behaviour MeaningGame.Steward

  alias MeaningGame.Steward
  alias MeaningGame.Steward.Assay
  alias MeaningGame.Steward.Gate
  alias MeaningGame.Steward.Precedent

  @impl true
  def assay(%{anchors: anchors, bridges: [left, right]}) do
    role = Steward.role(:assayer)
    model = role.model
    prompt_version = Map.get(role, :prompt_version, Assay.version())

    case Precedent.get(model, prompt_version, anchors, [left, right]) do
      {:ok, verdict} ->
        {:ok, verdict}

      :miss ->
        with {:ok, verdict} <- grade_live(role, anchors, left, right, prompt_version) do
          Precedent.put(model, prompt_version, anchors, [left, right], verdict)
          {:ok, verdict}
        end
    end
  end

  @impl true
  def author(chapter, opts \\ []) do
    role = Steward.role(:author)
    give = Keyword.get(opts, :give)
    digest = Keyword.get(opts, :digest)
    prompt = MeaningGame.Steward.Author.prompt(chapter, give, digest)

    case Gate.answer(role, prompt, &MeaningGame.Steward.Author.check/1) do
      {:ok, answer} ->
        {:ok, MeaningGame.Steward.Author.page(answer.json, chapter, give, answer)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp grade_live(role, anchors, left, right, prompt_version) do
    [forward, reverse] =
      [{left, right}, {right, left}]
      |> Enum.map(fn {first, second} ->
        Task.async(fn -> graded(role, anchors, first, second) end)
      end)
      # The grading's whole budget: one request's timeout is `timeout_ms`, and
      # this is what all of them together, retries included, may spend before
      # the game is told there is no verdict.
      |> await(role.deadline_ms)

    with {:ok, forward} <- forward, {:ok, reverse} <- reverse do
      {:ok, reconciled(forward, reverse, prompt_version)}
    end
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

  defp graded(role, anchors, first, second) do
    prompt = Assay.prompt(anchors, first, second)

    case first_answer(role.requests, fn -> Gate.answer(role, prompt, &Assay.check/1) end) do
      {:ok, answer} ->
        {:ok, Map.merge(Assay.verdict(answer.json), Map.take(answer, [:model, :cost_usd]))}

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
  # one's, because one reveal shows one sentence and one joke. The reverse
  # ordering's own reasoning is kept beside them rather than thrown away: when
  # the couple argue with a grade, the two arguments the model made are the
  # evidence.
  #
  # The cost is both orderings' answers, retries included — and not the hedged
  # requests that lost, whose usage nobody waited around to hear.
  defp reconciled(forward, reverse, prompt_version) do
    %{
      closeness: round((forward.closeness + reverse.closeness) / 2),
      reasoning: forward.reasoning,
      quip: forward.quip,
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
end
