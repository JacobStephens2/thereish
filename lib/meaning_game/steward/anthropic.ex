defmodule MeaningGame.Steward.Anthropic do
  @moduledoc """
  Anthropic models (Fable 5.1 as Author) through their Messages API.

  Fable 5.1 runs at max effort with JSON Schema constrained decoding.
  Server-side refusal fallbacks are opted in via beta header, and
  stop_reason: "max_tokens" is surfaced directly for terminal handling.
  """
  @behaviour MeaningGame.Steward.Provider

  require Logger

  alias MeaningGame.Steward.Provider

  @url "https://api.anthropic.com/v1/messages"
  @version "2023-06-01"
  @fallback_beta "server-side-fallback-2026-07-01"

  @impl true
  def complete(request) do
    with {:ok, key} <- api_key(request) do
      headers = [
        {"x-api-key", key},
        {"anthropic-version", @version},
        {"anthropic-beta", @fallback_beta},
        {"content-type", "application/json"}
      ]

      [
        headers: headers,
        json: body(request),
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
    Logger.error("ANTHROPIC_API_KEY is not set; the Author cannot pre-generate anything")
    {:error, :no_api_key}
  end

  defp body(request) do
    payload = %{
      model: request.model,
      max_tokens: request.max_tokens,
      messages: [%{role: "user", content: request.user}]
    }

    payload =
      if request[:system] do
        Map.put(payload, :system, request.system)
      else
        payload
      end

    output_config =
      %{}
      |> put_if(:effort, request[:effort])
      |> put_if(
        :format,
        if(request[:schema], do: %{type: "json_schema", schema: request.schema})
      )

    if output_config != %{} do
      Map.put(payload, :output_config, output_config)
    else
      payload
    end
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, val), do: Map.put(map, key, val)

  defp answer({:ok, %Req.Response{status: 200, body: body}}) do
    model = Map.get(body, "model")
    stop_reason = Map.get(body, "stop_reason")
    usage = Map.get(body, "usage", %{})
    input_tokens = Map.get(usage, "input_tokens", 0)
    output_tokens = Map.get(usage, "output_tokens", 0)

    content_text =
      body
      |> Map.get("content", [])
      |> Enum.find_value(fn
        %{"type" => "text", "text" => text} -> text
        _ -> nil
      end)

    {:ok,
     %{
       json: decode(content_text),
       model: model,
       stop_reason: stop_reason,
       cost_usd: Provider.cost(model, input_tokens, output_tokens)
     }}
  end

  defp answer({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, {:http, status, body}}

  defp answer({:error, reason}), do: {:error, reason}

  defp decode(nil), do: nil

  defp decode(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, json} when is_map(json) -> json
      _ -> nil
    end
  end
end
