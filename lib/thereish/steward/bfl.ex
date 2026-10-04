defmodule Thereish.Steward.Bfl do
  @moduledoc """
  Black Forest Labs FLUX.2 provider for the Limner.

  Submits to `/v1/flux-2-flex`, polls the returned URL, and downloads the
  sample before it expires. A seed and optional reference images keep a night's
  Masks in one style. Moderated content is `{:error, :refused}`.
  """

  @behaviour Thereish.Steward.Provider

  alias Thereish.Steward.Provider

  @base_url "https://api.bfl.ai"
  @default_model "flux-2-flex"
  @default_timeout_ms 30_000
  @default_deadline_ms 60_000
  @default_poll_ms 500

  @impl Provider
  def credentials, do: [api_key: "BFL_API_KEY"]

  @spec generate(map() | keyword()) :: {:ok, map()} | {:error, term()}
  def generate(request) when is_list(request), do: request |> Map.new() |> generate()

  def generate(request) when is_map(request) do
    with {:ok, key} <- api_key(request) do
      timeout_ms = get(request, :timeout_ms, @default_timeout_ms)
      deadline_ms = get(request, :deadline_ms, @default_deadline_ms)
      poll_ms = get(request, :poll_interval_ms, @default_poll_ms)
      model = get(request, :model, @default_model)
      size = size_int(get(request, :size, 512))
      prompt = get(request, :prompt, "")
      seed = get(request, :seed, 84)
      safety = get(request, :safety_tolerance, 5)
      references = List.wrap(get(request, :references, []))

      body =
        %{
          prompt: prompt,
          width: size,
          height: size,
          seed: seed,
          safety_tolerance: safety,
          output_format: "png"
        }
        |> put_references(references)

      path = path_for(model)

      with {:ok, polling_url} <- submit(key, path, body, timeout_ms),
           {:ok, sample} <-
             poll(
               key,
               polling_url,
               timeout_ms,
               System.monotonic_time(:millisecond) + deadline_ms,
               poll_ms
             ),
           {:ok, bytes} <-
             Provider.get_bytes(sample, timeout_ms: timeout_ms, provider: __MODULE__) do
        {:ok,
         %{
           bytes: bytes,
           format: :png,
           model: model,
           cost_usd: Provider.image_cost(model, size, size)
         }}
      end
    end
  end

  defp submit(key, path, body, timeout_ms) do
    [
      url: "#{@base_url}#{path}",
      headers: [{"x-key", key}, {"accept", "application/json"}],
      json: body,
      receive_timeout: timeout_ms,
      retry: false
    ]
    |> Keyword.merge(Provider.http_options(__MODULE__))
    |> Req.post()
    |> case do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        decoded = Provider.decode_body(body)

        case decoded["polling_url"] do
          url when is_binary(url) and url != "" -> {:ok, url}
          _ -> {:error, {:no_polling_url, decoded}}
        end

      {:ok, %Req.Response{status: status, body: body}} ->
        decoded = Provider.decode_body(body)

        if Provider.refused?(status, decoded) do
          {:error, :refused}
        else
          {:error, {:http, status, decoded}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp poll(key, url, timeout_ms, deadline, poll_ms) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:error, :timeout}
    else
      req =
        [
          url: url,
          headers: [{"x-key", key}, {"accept", "application/json"}],
          receive_timeout: timeout_ms,
          retry: false
        ]
        |> Keyword.merge(Provider.http_options(__MODULE__))

      case Req.get(req) do
        {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
          decoded = Provider.decode_body(body)

          case decoded["status"] do
            "Ready" ->
              case get_in(decoded, ["result", "sample"]) do
                sample when is_binary(sample) and sample != "" -> {:ok, sample}
                _ -> {:error, {:no_image, decoded}}
              end

            status when status in ["Request Moderated", "Content Moderated", "Moderated"] ->
              {:error, :refused}

            status when status in ["Error", "Failed"] ->
              {:error, {:failed, decoded}}

            _pending ->
              Process.sleep(poll_ms)
              poll(key, url, timeout_ms, deadline, poll_ms)
          end

        {:ok, %Req.Response{status: status, body: body}} ->
          decoded = Provider.decode_body(body)

          if Provider.refused?(status, decoded) do
            {:error, :refused}
          else
            {:error, {:http, status, decoded}}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp put_references(body, []), do: body

  defp put_references(body, [first | rest]) do
    body = Map.put(body, :input_image, Base.encode64(first))

    rest
    |> Enum.with_index(2)
    |> Enum.reduce(body, fn {bytes, i}, acc ->
      Map.put(acc, :"input_image_#{i}", Base.encode64(bytes))
    end)
  end

  defp path_for("flux-2-flex"), do: "/v1/flux-2-flex"
  defp path_for("flux-2-pro"), do: "/v1/flux-2-pro"
  defp path_for("flux-2-max"), do: "/v1/flux-2-max"
  defp path_for("flux-2-klein"), do: "/v1/flux-2-klein"
  defp path_for(_), do: "/v1/flux-2-flex"

  defp size_int(n) when is_integer(n), do: n

  defp size_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> 512
    end
  end

  defp size_int(_), do: 512

  defp get(request, key, default) do
    Map.get(request, key) || Map.get(request, to_string(key), default)
  end

  defp api_key(request) do
    case get(request, :api_key, nil) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :no_api_key}
    end
  end
end
