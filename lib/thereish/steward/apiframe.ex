defmodule Thereish.Steward.Apiframe do
  @moduledoc """
  Suno instrumental music through APIFRAME, a gateway (ticket 277).

  Suno has no public API of its own, so every route to it is a wrapper like
  this one, and that is why it is the alternative rather than the house
  provider (ADR-0025). A generation submits a job, polls it until it completes
  or the deadline passes, and downloads the first of the two tracks Suno
  answers. Confirmed against the endpoint on 2026-10-26: `V5_5` is the newest
  model version it accepts, and a job completes in 24–43 s.
  """

  @behaviour Thereish.Steward.Provider

  require Logger

  alias Thereish.Steward.Provider

  @base_url "https://api.apiframe.ai/v2"

  # Suno's description mode takes at most 500 characters.
  @prompt_limit 500

  @impl Provider
  def credentials, do: [api_key: "APIFRAME_API_KEY"]

  @spec generate(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def generate(request) when is_list(request), do: request |> Map.new() |> generate()

  def generate(request) when is_map(request) do
    model = Map.get(request, :model) || "V5_5"
    timeout_ms = Map.get(request, :timeout_ms, 30_000)

    with {:ok, key} <- api_key(request),
         {:ok, job_id} <- submit(request.prompt, model, key, timeout_ms),
         deadline = System.monotonic_time(:millisecond) + Map.get(request, :deadline_ms, 180_000),
         {:ok, track} <-
           poll(job_id, key, deadline, Map.get(request, :poll_interval_ms, 3_000), timeout_ms),
         {:ok, bytes} <-
           Provider.get_bytes(track["audioUrl"], timeout_ms: timeout_ms, provider: __MODULE__) do
      {:ok,
       %{
         bytes: bytes,
         url: track["audioUrl"],
         duration: track["duration"] && round(track["duration"]),
         model: model,
         cost_usd: Provider.track_cost(model)
       }}
    end
  end

  defp submit(prompt, model, key, timeout_ms) do
    body = %{
      prompt: String.slice(prompt, 0, @prompt_limit),
      model: "suno",
      sunoParams: %{model_version: model, instrumental: true}
    }

    case Req.post(req(key, timeout_ms, url: "#{@base_url}/music/generate", json: body)) do
      {:ok, %Req.Response{status: status, body: %{"jobId" => id}}} when status in 200..299 ->
        {:ok, id}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http, status, Provider.decode_body(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp poll(job_id, key, deadline, interval_ms, timeout_ms) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :timeout}
    else
      case Req.get(req(key, timeout_ms, url: "#{@base_url}/jobs/#{job_id}")) do
        {:ok, %Req.Response{status: 200, body: %{"status" => "COMPLETED"} = job}} ->
          case get_in(job, ["result", "tracks"]) do
            [%{"audioUrl" => url} = track | _] when is_binary(url) -> {:ok, track}
            _ -> {:error, :no_tracks}
          end

        {:ok, %Req.Response{status: 200, body: %{"status" => "FAILED"} = job}} ->
          {:error, {:failed, job["error"]}}

        {:ok, %Req.Response{status: 200}} ->
          Process.sleep(interval_ms)
          poll(job_id, key, deadline, interval_ms, timeout_ms)

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:http, status, Provider.decode_body(body)}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp req(key, timeout_ms, opts) do
    [headers: [{"x-api-key", key}], receive_timeout: timeout_ms, retry: false]
    |> Keyword.merge(opts)
    |> Keyword.merge(Provider.http_options(__MODULE__))
  end

  defp api_key(%{api_key: key}) when is_binary(key) and key != "", do: {:ok, key}

  defp api_key(_request) do
    Logger.error("APIFRAME_API_KEY is not set; Foley cannot score a Track")
    {:error, :no_api_key}
  end
end
