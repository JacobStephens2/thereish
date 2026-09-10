defmodule Thereish.Steward.Recraft do
  @moduledoc """
  Recraft image provider for the Limner.

  V4 Styles (`recraftv4_styles`) needs a `style_id` or style-reference images.
  Without them the call falls back to `recraftv4` so the bake-off can run before
  a house reference set exists.
  """

  alias Thereish.Steward.Provider

  @base_url "https://external.api.recraft.ai"
  @default_model "recraftv4_styles"
  @fallback_model "recraftv4"
  @default_timeout_ms 30_000

  @spec generate(map() | keyword()) :: {:ok, map()} | {:error, term()}
  def generate(request) when is_list(request), do: request |> Map.new() |> generate()

  def generate(request) when is_map(request) do
    with {:ok, key} <- api_key(request) do
      timeout_ms = get(request, :timeout_ms, @default_timeout_ms)
      wanted = get(request, :model, @default_model)
      references = List.wrap(get(request, :references, []))
      style_id = get(request, :style_id, nil)
      prompt = get(request, :prompt, "")
      size = size_string(get(request, :size, 512))

      {model, body, content} =
        cond do
          is_binary(style_id) and style_id != "" ->
            {wanted,
             %{
               prompt: prompt,
               model: wanted,
               n: 1,
               response_format: "b64_json",
               size: size,
               style_id: style_id
             }, :json}

          references != [] ->
            {wanted, {prompt, wanted, size, references}, :multipart}

          wanted in ["recraftv4_styles", "recraftv4_styles_pro"] ->
            {@fallback_model,
             %{
               prompt: prompt,
               model: @fallback_model,
               n: 1,
               response_format: "b64_json",
               size: size
             }, :json}

          true ->
            {wanted,
             %{
               prompt: prompt,
               model: wanted,
               n: 1,
               response_format: "b64_json",
               size: size
             }, :json}
        end

      post(key, timeout_ms, model, body, content)
    end
  end

  defp post(key, timeout_ms, model, body, :json) do
    [
      url: "#{@base_url}/v1/images/generations",
      headers: [{"authorization", "Bearer #{key}"}],
      json: body,
      receive_timeout: timeout_ms,
      retry: false
    ]
    |> Keyword.merge(Provider.http_options(__MODULE__))
    |> Req.post()
    |> answer(model, timeout_ms)
  end

  defp post(key, timeout_ms, model, {prompt, model_name, size, references}, :multipart) do
    files =
      Enum.with_index(references, 1)
      |> Enum.map(fn {bytes, i} ->
        {"style_references", {bytes, filename: "ref-#{i}.png", content_type: "image/png"}}
      end)

    form =
      [
        {"prompt", prompt},
        {"model", model_name},
        {"n", "1"},
        {"response_format", "b64_json"},
        {"size", size}
      ] ++ files

    [
      url: "#{@base_url}/v1/images/generations",
      headers: [{"authorization", "Bearer #{key}"}],
      form: form,
      receive_timeout: timeout_ms,
      retry: false
    ]
    |> Keyword.merge(Provider.http_options(__MODULE__))
    |> Req.post()
    |> answer(model, timeout_ms)
  end

  defp answer({:ok, %Req.Response{status: status, body: body}}, model, timeout_ms)
       when status in 200..299 do
    decoded = Provider.decode_body(body)
    first = get_in(decoded, ["data", Access.at(0)]) || %{}

    cond do
      is_binary(first["b64_json"]) ->
        case decode_png(first["b64_json"]) do
          {:ok, bytes} ->
            {:ok,
             %{
               bytes: bytes,
               format: :png,
               model: model,
               cost_usd: Provider.image_cost(model)
             }}

          error ->
            error
        end

      is_binary(first["url"]) and first["url"] != "" ->
        with {:ok, bytes} <-
               Provider.get_bytes(first["url"], timeout_ms: timeout_ms, provider: __MODULE__) do
          {:ok,
           %{
             bytes: bytes,
             format: :png,
             model: model,
             cost_usd: Provider.image_cost(model)
           }}
        end

      true ->
        {:error, {:no_image, decoded}}
    end
  end

  defp answer({:ok, %Req.Response{status: status, body: body}}, _model, _timeout_ms) do
    decoded = Provider.decode_body(body)

    if Provider.refused?(status, decoded) do
      {:error, :refused}
    else
      {:error, {:http, status, decoded}}
    end
  end

  defp answer({:error, reason}, _model, _timeout_ms), do: {:error, reason}

  defp decode_png("data:image/" <> rest) do
    case String.split(rest, ",", parts: 2) do
      [_meta, data] -> decode_png(data)
      _ -> {:error, :bad_image}
    end
  end

  defp decode_png(b64) when is_binary(b64) do
    case Base.decode64(b64, padding: :ignore) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, :bad_image}
    end
  end

  # Recraft V4 is billed at 1MP; 512² is not a supported size.
  defp size_string(n) when is_integer(n) and n < 1024, do: "1024x1024"
  defp size_string(n) when is_integer(n), do: "#{n}x#{n}"
  defp size_string("512x512"), do: "1024x1024"
  defp size_string(s) when is_binary(s), do: s
  defp size_string(_), do: "1024x1024"

  defp get(request, key, default) do
    Map.get(request, key) || Map.get(request, to_string(key), default)
  end

  defp api_key(request) do
    cond do
      present?(get(request, :recraft_api_key, nil)) -> {:ok, get(request, :recraft_api_key, nil)}
      present?(get(request, :api_key, nil)) -> {:ok, get(request, :api_key, nil)}
      true -> {:error, :no_api_key}
    end
  end

  defp present?(key) when is_binary(key) and key != "", do: true
  defp present?(_), do: false
end
