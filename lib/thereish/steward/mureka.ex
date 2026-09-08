defmodule Thereish.Steward.Mureka do
  @moduledoc """
  Mureka instrumental music provider.

  Starts an instrumental generation job, polls until completion or deadline,
  and downloads the chosen audio URL.
  """

  require Logger

  alias Thereish.Steward.Provider

  @base_url "https://api.mureka.ai"

  @typedoc "An instrumental music generation request"
  @type request :: %{
          required(:prompt) => String.t(),
          optional(:model) => String.t(),
          optional(:n) => pos_integer(),
          optional(:api_key) => String.t() | nil,
          optional(:deadline_ms) => pos_integer(),
          optional(:poll_interval_ms) => pos_integer(),
          optional(:timeout_ms) => pos_integer()
        }

  @typedoc "An instrumental music generation response"
  @type response :: %{
          bytes: binary(),
          url: String.t(),
          model: String.t(),
          cost_usd: float()
        }

  @typedoc "An instrumental music streaming response"
  @type stream_response :: %{
          task_id: String.t(),
          stream_url: String.t(),
          url: String.t() | nil,
          status: String.t(),
          duration: non_neg_integer(),
          model: String.t(),
          time_to_stream_ms: non_neg_integer(),
          cost_usd: float()
        }

  @spec generate(request() | keyword() | map()) :: {:ok, response()} | {:error, term()}
  def generate(request) when is_list(request), do: request |> Map.new() |> generate()

  def generate(request) when is_map(request) do
    with {:ok, key} <- api_key(request) do
      opts = parse_job_opts(request, key)

      with {:ok, task_id} <- start_job(opts.prompt, opts.model, opts.n, key, opts.timeout_ms),
           {:ok, choice} <- poll_job(task_id, opts.poll_opts),
           {:ok, bytes} <- download_url(choice.url, opts.timeout_ms) do
        {:ok,
         %{
           bytes: bytes,
           url: choice.url,
           duration: choice.duration,
           model: opts.model,
           cost_usd: Provider.track_cost(opts.model)
         }}
      end
    end
  end

  @doc """
  Starts an instrumental generation job with `stream: true`, polls until a `stream_url`
  is available, and returns stream metadata without waiting for the full file download.
  """
  @spec stream(request() | keyword() | map()) :: {:ok, stream_response()} | {:error, term()}
  def stream(request) when is_list(request), do: request |> Map.new() |> stream()

  def stream(request) when is_map(request) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, key} <- api_key(request) do
      opts = parse_job_opts(request, key)

      with {:ok, task_id} <-
             start_job(opts.prompt, opts.model, opts.n, key, opts.timeout_ms, true),
           {:ok, info} <- poll_stream_job(task_id, opts.poll_opts) do
        elapsed = System.monotonic_time(:millisecond) - start_time

        {:ok,
         %{
           task_id: task_id,
           stream_url: info.stream_url,
           url: info.url,
           status: info.status,
           duration: info.duration,
           model: opts.model,
           time_to_stream_ms: elapsed,
           cost_usd: Provider.track_cost(opts.model)
         }}
      end
    end
  end

  defp start_job(prompt, model, n, key, timeout_ms, stream \\ false) do
    body = %{prompt: prompt, model: model, n: n}
    body = if stream, do: Map.put(body, :stream, true), else: body
    url = "#{@base_url}/v1/instrumental/generate"

    opts =
      [
        url: url,
        headers: [{"authorization", "Bearer #{key}"}],
        json: body,
        receive_timeout: timeout_ms,
        retry: false
      ]
      |> Keyword.merge(Provider.http_options(__MODULE__))

    case Req.post(opts) do
      {:ok, %Req.Response{status: 200, body: %{"id" => task_id}}} when is_binary(task_id) ->
        {:ok, task_id}

      {:ok, %Req.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"id" => task_id}} when is_binary(task_id) -> {:ok, task_id}
          _ -> {:error, :no_task_id}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http, status, Provider.decode_body(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp poll_job(task_id, %{deadline_time: deadline_time} = opts) do
    if System.monotonic_time(:millisecond) >= deadline_time do
      {:error, :timeout}
    else
      url = "#{@base_url}/v1/instrumental/query/#{task_id}"

      req_opts =
        [
          url: url,
          headers: [{"authorization", "Bearer #{opts.key}"}],
          receive_timeout: opts.timeout_ms,
          retry: false
        ]
        |> Keyword.merge(Provider.http_options(__MODULE__))

      case Req.get(req_opts) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          parsed = Provider.decode_body(body)

          case parsed["status"] do
            "succeeded" ->
              choice = get_in(parsed, ["choices", Access.at(0)]) || %{}
              url = choice["url"]
              duration = choice["duration"] || parsed["duration"] || 120

              case url do
                url when is_binary(url) and url != "" -> {:ok, %{url: url, duration: duration}}
                _ -> {:error, :no_choices}
              end

            status when status in ["failed", "cancelled", "timeouted"] ->
              {:error, {:failed, status}}

            _other ->
              Process.sleep(opts.poll_interval_ms)
              poll_job(task_id, opts)
          end

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:http, status, Provider.decode_body(body)}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp poll_stream_job(task_id, %{deadline_time: deadline_time} = opts) do
    if System.monotonic_time(:millisecond) >= deadline_time do
      {:error, :timeout}
    else
      url = "#{@base_url}/v1/instrumental/query/#{task_id}"

      req_opts =
        [
          url: url,
          headers: [{"authorization", "Bearer #{opts.key}"}],
          receive_timeout: opts.timeout_ms,
          retry: false
        ]
        |> Keyword.merge(Provider.http_options(__MODULE__))

      case Req.get(req_opts) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          parsed = Provider.decode_body(body)
          choice = get_in(parsed, ["choices", Access.at(0)]) || %{}
          stream_url = choice["stream_url"] || parsed["stream_url"]
          final_url = choice["url"] || parsed["url"]
          duration = choice["duration"] || parsed["duration"] || 120
          status = parsed["status"]

          cond do
            is_binary(stream_url) and stream_url != "" ->
              {:ok,
               %{
                 stream_url: stream_url,
                 url: final_url,
                 status: status,
                 duration: duration
               }}

            status == "succeeded" and is_binary(final_url) and final_url != "" ->
              {:ok,
               %{
                 stream_url: final_url,
                 url: final_url,
                 status: status,
                 duration: duration
               }}

            status in ["failed", "cancelled", "timeouted"] ->
              {:error, {:failed, status}}

            true ->
              Process.sleep(opts.poll_interval_ms)
              poll_stream_job(task_id, opts)
          end

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:http, status, Provider.decode_body(body)}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp download_url(url, timeout_ms) do
    opts =
      [
        url: url,
        receive_timeout: timeout_ms,
        retry: false
      ]
      |> Keyword.merge(Provider.http_options(__MODULE__))

    case Req.get(opts) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:download_failed, {:http, status, body}}}

      {:error, reason} ->
        {:error, {:download_failed, reason}}
    end
  end

  defp parse_job_opts(request, key) do
    deadline_ms = Map.get(request, :deadline_ms) || Map.get(request, "deadline_ms", 180_000)

    poll_interval_ms =
      Map.get(request, :poll_interval_ms) || Map.get(request, "poll_interval_ms", 2_000)

    timeout_ms = Map.get(request, :timeout_ms) || Map.get(request, "timeout_ms", 30_000)

    %{
      model: Map.get(request, :model) || Map.get(request, "model", "auto"),
      n: Map.get(request, :n) || Map.get(request, "n", 1),
      prompt: Map.get(request, :prompt) || Map.get(request, "prompt"),
      timeout_ms: timeout_ms,
      poll_opts: %{
        key: key,
        deadline_time: System.monotonic_time(:millisecond) + deadline_ms,
        poll_interval_ms: poll_interval_ms,
        timeout_ms: timeout_ms
      }
    }
  end

  defp api_key(request) do
    case Map.get(request, :api_key) || Map.get(request, "api_key") do
      key when is_binary(key) and key != "" ->
        {:ok, key}

      _ ->
        Logger.error("MUREKA_API_KEY is not set; Foley cannot generate music")
        {:error, :no_api_key}
    end
  end
end
