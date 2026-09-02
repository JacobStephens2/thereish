defmodule Keeper.Schema do
  @moduledoc "The deterministic gate with the last word (design law 14): validate every model output; reject and regenerate on failure."

  def validate(schema, data) do
    root = JSV.build!(Keeper.Prompts.to_map(schema))

    case JSV.validate(data, root) do
      {:ok, _} -> :ok
      {:error, err} -> {:error, "schema: " <> (err |> JSV.normalize_error() |> Jason.encode!() |> String.slice(0, 600))}
    end
  end

  @doc """
  Call the adapter, validate JSON against the schema and an extra deterministic check, and
  regenerate with feedback up to `retries` times. Returns {:ok, result, attempts} | {:error, why, attempts}.
  """
  def generate(cfg, req, check \\ fn _ -> :ok end, retries \\ 2) do
    req = Map.merge(req, Map.take(cfg, [:model, :effort, :max_tokens, :fallbacks]))
    loop(cfg, req, check, retries, [])
  end

  defp loop(cfg, req, check, left, attempts) do
    case cfg.adapter.complete(req, []) do
      {:ok, %{stop_reason: "refusal"} = res} ->
        {:error, {:refusal, res.meta[:stop_details]}, Enum.reverse([{:refusal, res} | attempts])}

      {:ok, %{json: nil} = res} ->
        why = "The output was not a JSON object (stop_reason=#{res.stop_reason})."
        retry(cfg, req, check, left, [{:rejected, why, res} | attempts], why)

      {:ok, res} ->
        with :ok <- validate(req.schema, res.json), :ok <- check.(res.json) do
          {:ok, res, Enum.reverse([{:ok, res} | attempts])}
        else
          {:error, why} -> retry(cfg, req, check, left, [{:rejected, why, res} | attempts], why)
        end

      {:error, e} ->
        {:error, e, Enum.reverse(attempts)}
    end
  end

  defp retry(_cfg, _req, _check, 0, attempts, why), do: {:error, {:rejected, why}, Enum.reverse(attempts)}

  defp retry(cfg, req, check, left, attempts, why) do
    IO.puts("  ↻ rejected: #{why} — regenerating (#{left} left)")
    req = %{req | user: req.user <> "\n\nYour previous answer was rejected by the validator: #{why}\nProduce a corrected answer."}
    loop(cfg, req, check, left - 1, attempts)
  end
end
