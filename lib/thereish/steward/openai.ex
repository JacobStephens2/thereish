defmodule Thereish.Steward.OpenAI do
  @moduledoc """
  OpenAI models (GPT-6 Astra as Author) through their Chat Completions API.

  Runs at low reasoning effort with JSON Schema constrained structured output.
  A refusal from the model or a content filter yields a response with `json: nil`
  and the refusal text surfaced under `:refusal` and `stop_reason: "refusal"`.
  """
  @behaviour Thereish.Steward.Provider

  require Logger

  alias Thereish.Steward.Provider

  @url "https://api.openai.com/v1/chat/completions"

  @impl true
  def complete(request) do
    with {:ok, key} <- api_key(request) do
      [
        json: body(request),
        auth: {:bearer, key},
        receive_timeout: request.timeout_ms,
        retry: false
      ]
      |> Keyword.merge(Provider.http_options(__MODULE__))
      |> then(&Req.post(@url, &1))
      |> answer()
    end
  end

  defp api_key(%{api_key: key}) when is_binary(key) and key != "", do: {:ok, key}

  defp api_key(_request) do
    Logger.error("OPENAI_API_KEY is not set; the Author cannot write Bookends with Astra")
    {:error, :no_api_key}
  end

  defp body(request) do
    %{
      model: request.model,
      messages: [
        %{role: "system", content: request.system},
        %{role: "user", content: request.user}
      ],
      response_format: %{
        type: "json_schema",
        json_schema: %{name: request.schema_name, strict: true, schema: request.schema}
      }
    }
    |> maybe_put(:reasoning_effort, request[:effort])
    |> maybe_put(:max_completion_tokens, request[:max_tokens])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp answer({:ok, %Req.Response{status: 200, body: body}}) do
    choice = body |> Map.get("choices", []) |> List.first(%{})
    message = Map.get(choice, "message", %{})
    model = Map.get(body, "model")
    finish_reason = Map.get(choice, "finish_reason")
    refusal = Map.get(message, "refusal")
    usage = Map.get(body, "usage", %{})
    cost_usd = cost(model, usage)

    if is_binary(refusal) and refusal != "" do
      {:ok,
       %{
         json: nil,
         model: model,
         stop_reason: finish_reason || "refusal",
         refusal: refusal,
         cost_usd: cost_usd
       }}
    else
      {:ok,
       %{
         json: decode(Map.get(message, "content")),
         model: model,
         stop_reason: finish_reason,
         cost_usd: cost_usd
       }}
    end
  end

  defp answer({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:http, status, body}}
  end

  defp answer({:error, reason}), do: {:error, reason}

  defp decode(nil), do: nil

  defp decode(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, json} when is_map(json) -> json
      _ -> nil
    end
  end

  defp cost(model, usage) do
    input = Map.get(usage, "prompt_tokens", 0)
    output = Map.get(usage, "completion_tokens", 0)

    Provider.cost(model, input, output)
  end
end
