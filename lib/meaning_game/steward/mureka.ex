defmodule MeaningGame.Steward.Mureka do
  @moduledoc """
  Mureka instrumental music provider.

  Starts an instrumental generation job, polls until completion or deadline,
  and downloads the chosen audio URL.
  """

  require Logger

  alias MeaningGame.Steward.Provider

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

  @spec generate(request() | keyword() | map()) :: {:ok, response()} | {:error, term()}
  def generate(request) when is_list(request), do: request |> Map.new() |> generate()

  def generate(request) when is_map(request) do
    with {:ok, key} <- api_key(request) do
      model = Map.get(request, :model) || Map.get(request, "model", "auto")
      n = Map.get(request, :n) || Map.get(request, "n", 1)
      prompt = Map.get(request, :prompt) || Map.get(request, "prompt")
      deadline_ms = Map.get(request, :deadline_ms) || Map.get(request, "deadline_ms", 180_000)

      poll_interval_ms =
        Map.get(request, :poll_interval_ms) || Map.get(request, "poll_interval_ms", 2_000)

      timeout_ms = Map.get(request, :timeout_ms) || Map.get(request, "timeout_ms", 30_000)

      poll_opts = %{
        key: key,
        deadline_time: System.monotonic_time(:millisecond) + deadline_ms,
        poll_interval_ms: poll_interval_ms,
        timeout_ms: timeout_ms
      }

      with {:ok, task_id} <- start_job(prompt, model, n, key, timeout_ms),
           {:ok, choice} <- poll_job(task_id, poll_opts),
           {:ok, bytes} <- download_url(choice.url, timeout_ms) do
        {:ok,
         %{
           bytes: bytes,
           url: choice.url,
           duration: choice.duration,
           model: model,
           cost_usd: Provider.track_cost(model)
         }}
      end
    end
  end

  defp start_job(prompt, model, n, key, timeout_ms) do
    body = %{prompt: prompt, model: model, n: n}
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
