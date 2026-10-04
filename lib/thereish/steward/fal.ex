defmodule Thereish.Steward.Fal do
  @moduledoc """
  fal.ai hosted FLUX.1 schnell — the Limner's zero-cost fallback.

  One configuration line away from the bake-off winner. A seed keeps a night's
  Masks in one style; there is no house-style mechanism beyond the prompt.
  """

  @behaviour Thereish.Steward.Provider

  alias Thereish.Steward.Provider

  @url "https://fal.run/fal-ai/flux/schnell"
  @default_model "fal-ai/flux/schnell"
  @default_timeout_ms 30_000

  @impl Provider
  def credentials, do: [api_key: "FAL_AI_API_KEY"]

  @spec generate(map() | keyword()) :: {:ok, map()} | {:error, term()}
  def generate(request) when is_list(request), do: request |> Map.new() |> generate()

  def generate(request) when is_map(request) do
    with {:ok, key} <- api_key(request) do
      timeout_ms = get(request, :timeout_ms, @default_timeout_ms)
      model = get(request, :model, @default_model)
      prompt = get(request, :prompt, "")
      seed = get(request, :seed, 84)
      size = size_int(get(request, :size, 512))

      body = %{
        prompt: prompt,
        image_size: %{width: size, height: size},
        num_inference_steps: 4,
        seed: seed,
        enable_safety_checker: true,
        output_format: "png",
        sync_mode: true
      }

      [
        url: @url,
        headers: [{"authorization", "Key #{key}"}],
        json: body,
        receive_timeout: timeout_ms,
        retry: false
      ]
      |> Keyword.merge(Provider.http_options(__MODULE__))
      |> Req.post()
      |> answer(model, size, timeout_ms)
    end
  end

  defp answer({:ok, %Req.Response{status: status, body: body}}, model, size, timeout_ms)
       when status in 200..299 do
    decoded = Provider.decode_body(body)
    image = get_in(decoded, ["images", Access.at(0)]) || %{}

    cond do
      nsfw?(decoded) ->
        {:error, :refused}

      is_binary(image["url"]) and String.starts_with?(image["url"], "data:") ->
        with {:ok, bytes} <- decode_data_uri(image["url"]) do
          ok(bytes, model, size)
        end

      is_binary(image["url"]) ->
        with {:ok, bytes} <-
               Provider.get_bytes(image["url"], timeout_ms: timeout_ms, provider: __MODULE__) do
          ok(bytes, model, size)
        end

      true ->
        {:error, {:no_image, decoded}}
    end
  end

  defp answer({:ok, %Req.Response{status: status, body: body}}, _model, _size, _timeout_ms) do
    decoded = Provider.decode_body(body)

    if Provider.refused?(status, decoded) do
      {:error, :refused}
    else
      {:error, {:http, status, decoded}}
    end
  end

  defp answer({:error, reason}, _model, _size, _timeout_ms), do: {:error, reason}

  defp ok(bytes, model, size) do
    {:ok,
     %{
       bytes: bytes,
       format: :png,
       model: model,
       cost_usd: Provider.image_cost(model, size, size)
     }}
  end

  defp nsfw?(decoded) do
    case decoded["has_nsfw_concepts"] do
      [true | _] -> true
      true -> true
      _ -> false
    end
  end

  defp decode_data_uri("data:" <> rest) do
    case String.split(rest, ",", parts: 2) do
      [_meta, data] ->
        case Base.decode64(data, padding: :ignore) do
          {:ok, bytes} -> {:ok, bytes}
          :error -> {:error, :bad_image}
        end

      _ ->
        {:error, :bad_image}
    end
  end

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
