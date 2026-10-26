defmodule Thereish.Steward.Lyria do
  @moduledoc """
  Google's Lyria instrumental music, through the Gemini API (ticket 277).

  One synchronous `generateContent` call answers the whole song as base64 MP3
  in an `inlineData` part, so there is no job to poll: `deadline_ms` is the
  request's receive timeout. Confirmed against the endpoint on 2026-10-26:
  `lyria-3.5` answers a ~3-minute 192 kbps song in 25–45 s, and
  `lyria-3-clip-preview` a 30-second one in ~8 s. An answer can come back with
  no candidates at all; that is an error here, not an empty Track.

  The key is the Gemini key the Assayer already uses.
  """

  @behaviour Thereish.Steward.Provider

  require Logger

  alias Thereish.Steward.Provider

  @base_url "https://generativelanguage.googleapis.com/v1beta/models"

  @impl Provider
  def credentials, do: [api_key: "GEMINI_API_KEY"]

  @spec generate(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def generate(request) when is_list(request), do: request |> Map.new() |> generate()

  def generate(request) when is_map(request) do
    model = Map.get(request, :model) || "lyria-3.5"

    with {:ok, key} <- api_key(request),
         {:ok, bytes} <-
           compose(request.prompt, model, key, Map.get(request, :deadline_ms, 180_000)) do
      {:ok, %{bytes: bytes, model: model, cost_usd: Provider.track_cost(model)}}
    end
  end

  defp compose(prompt, model, key, deadline_ms) do
    [
      url: "#{@base_url}/#{model}:generateContent",
      headers: [{"x-goog-api-key", key}],
      json: %{contents: [%{role: "user", parts: [%{text: prompt}]}]},
      receive_timeout: deadline_ms,
      retry: false
    ]
    |> Keyword.merge(Provider.http_options(__MODULE__))
    |> Req.post()
    |> answer()
  end

  defp answer({:ok, %Req.Response{status: 200, body: body}}) do
    body = Provider.decode_body(body)

    parts = get_in(body, ["candidates", Access.at(0), "content", "parts"]) || []

    case Enum.find_value(parts, &get_in(&1, ["inlineData", "data"])) do
      data when is_binary(data) -> Base.decode64(data) |> audio(body)
      nil -> {:error, {:no_audio, body}}
    end
  end

  defp answer({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, {:http, status, Provider.decode_body(body)}}

  defp answer({:error, reason}), do: {:error, reason}

  defp audio({:ok, bytes}, _body), do: {:ok, bytes}
  defp audio(:error, body), do: {:error, {:no_audio, body}}

  defp api_key(%{api_key: key}) when is_binary(key) and key != "", do: {:ok, key}

  defp api_key(_request) do
    Logger.error("GEMINI_API_KEY is not set; Foley cannot score a Track")
    {:error, :no_api_key}
  end
end
