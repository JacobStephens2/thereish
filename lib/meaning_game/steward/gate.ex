defmodule MeaningGame.Steward.Gate do
  @moduledoc """
  Nothing a model says reaches the game without coming through here.

  A schema validator has the last word (design law 14): the answer is decoded,
  checked against the role's JSON schema with `jsv`, and checked again by
  whatever else that role knows about its own answers. An answer that fails is
  not a crash and not a shrug — it is handed back to the model with the reason
  it was rejected, and asked again. Only when the retries are spent does the
  Steward report that it has no answer, which the game already has a rule for.

  This is the module the "malformed response is never a crash mid-Page"
  obligation lives in, so it is deliberately incurious about what the answer
  means. It knows a schema, a check, and how many times to ask; the Assayer's
  words are `MeaningGame.Steward.Assay`'s and the wire is the provider's.

  What comes back is the answer plus its provenance: which model gave it, what
  it cost across every attempt it took, and how long the whole exchange ran.
  Retries are counted into the cost and the clock on purpose — the couple waited
  through them.
  """

  require Logger

  @typedoc "One validated answer, and what getting it took."
  @type answer :: %{
          json: map(),
          model: String.t(),
          cost_usd: float(),
          latency_ms: non_neg_integer(),
          attempts: pos_integer()
        }

  @doc """
  Asks one model one question, and does not return an answer the validator
  rejected.

  `check` is the role's own last word on its own answers, run after the schema
  and before the game sees anything.
  """
  @spec answer(map(), map(), (map() -> :ok | {:error, String.t()})) ::
          {:ok, answer()} | {:error, term()}
  def answer(role, prompt, check) do
    started = System.monotonic_time(:millisecond)

    role
    |> ask(prompt, check, role.retries, {0.0, 0})
    |> stamp(started)
  end

  defp ask(role, prompt, check, retries_left, spent) do
    case role.provider.complete(request(role, prompt)) do
      {:ok, %{stop_reason: cap} = response} when cap in ["max_tokens", "length"] ->
        spent = add(spent, response)
        {:error, {:max_tokens, "hit the output token cap (stop_reason=#{cap})"}, spent}

      {:ok, response} ->
        spent = add(spent, response)

        case accept(response, prompt, check) do
          :ok -> {:ok, %{json: response.json, model: response.model}, spent}
          {:error, why} -> retry(role, prompt, check, retries_left, spent, why)
        end

      {:error, reason} ->
        {:error, reason, spent}
    end
  end

  # A rejected answer is asked again with the rejection quoted back, because a
  # model told what was wrong with its last answer usually fixes it, and a model
  # told nothing usually repeats it.
  defp retry(_role, _prompt, _check, 0, spent, why), do: {:error, {:rejected, why}, spent}

  defp retry(role, prompt, check, retries_left, spent, why) do
    Logger.warning("#{role.model} answered with something the validator rejected (#{why})")

    prompt = %{
      prompt
      | user:
          prompt.user <>
            "\n\nYour previous answer was rejected by the validator: #{why}\n" <>
            "Produce a corrected answer."
    }

    ask(role, prompt, check, retries_left - 1, spent)
  end

  defp accept(%{json: nil} = response, _prompt, _check) do
    {:error, "the answer was not a JSON object (stop_reason=#{response.stop_reason})"}
  end

  defp accept(%{json: json}, prompt, check) do
    with :ok <- validate(prompt.schema, json), do: check.(json)
  end

  defp validate(schema, json) do
    case JSV.validate(json, validator(schema)) do
      {:ok, _valid} ->
        :ok

      {:error, error} ->
        {:error,
         "schema: " <> (error |> JSV.normalize_error() |> Jason.encode!() |> String.slice(0, 600))}
    end
  end

  # Building a validator is compilation, and the schema it compiles is a
  # constant, so it is compiled once per schema for the life of the node rather
  # than once per grade inside the reveal beat.
  defp validator(schema) do
    key = {__MODULE__, schema}

    case :persistent_term.get(key, nil) do
      nil ->
        root = schema |> to_map() |> JSV.build!()
        :persistent_term.put(key, root)
        root

      root ->
        root
    end
  end

  # `jsv` wants plain maps; the wire wants the property order the schema was
  # written in. The schema is the ordered one, and this is the copy for the
  # validator.
  defp to_map(%Jason.OrderedObject{values: values}),
    do: Map.new(values, fn {key, value} -> {key, to_map(value)} end)

  defp to_map(list) when is_list(list), do: Enum.map(list, &to_map/1)
  defp to_map(other), do: other

  defp request(role, prompt) do
    Map.merge(prompt, Map.take(role, [:model, :effort, :max_tokens, :timeout_ms, :api_key]))
  end

  defp add({cost, attempts}, response), do: {cost + response.cost_usd, attempts + 1}

  defp stamp({:ok, answer, {cost, attempts}}, started) do
    {:ok,
     Map.merge(answer, %{
       cost_usd: cost,
       attempts: attempts,
       latency_ms: System.monotonic_time(:millisecond) - started
     })}
  end

  defp stamp({:error, reason, _spent}, _started), do: {:error, reason}
end
