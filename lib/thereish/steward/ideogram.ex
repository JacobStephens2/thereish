defmodule Thereish.Steward.Ideogram do
  @moduledoc """
  Ideogram 3.0 turbo image provider for the Limner.

  Style-reference images are attached when the house set is present. A dark Give
  the vendor will not draw comes back as `{:error, :refused}`.
  """

  @behaviour Thereish.Steward.Provider

  alias Thereish.Steward.Provider

  @url "https://api.ideogram.ai/v1/ideogram-v3/generate"
  @default_model "ideogram-v3-turbo"
  @default_timeout_ms 30_000

  @impl Provider
  def credentials, do: [api_key: "IDEOGRAM_API_KEY"]

  @spec generate(map() | keyword()) :: {:ok, map()} | {:error, term()}
  def generate(request) when is_list(request), do: request |> Map.new() |> generate()

  def generate(request) when is_map(request) do
    with {:ok, key} <- api_key(request) do
      timeout_ms = get(request, :timeout_ms, @default_timeout_ms)
      model = get(request, :model, @default_model)
      prompt = get(request, :prompt, "")
      seed = get(request, :seed, 84)
      speed = get(request, :rendering_speed, "TURBO")
      style_type = get(request, :style_type, "DESIGN")
      references = List.wrap(get(request, :references, []))

      fields = %{
        prompt: prompt,
        rendering_speed: to_string(speed),
        aspect_ratio: "1x1",
        style_type: to_string(style_type),
        seed: seed,
        magic_prompt: "OFF"
      }

      req =
        if references == [] do
          [
            url: @url,
            headers: [{"api-key", key}],
            json: fields,
            receive_timeout: timeout_ms,
            retry: false
          ]
        else
          files =
            Enum.with_index(references, 1)
            |> Enum.map(fn {bytes, i} ->
              {"style_reference_images",
               {bytes, filename: "ref-#{i}.png", content_type: "image/png"}}
            end)

          form =
            Enum.map(fields, fn {k, v} -> {to_string(k), to_string(v)} end) ++ files

          [
            url: @url,
            headers: [{"api-key", key}],
            form: form,
            receive_timeout: timeout_ms,
            retry: false
          ]
        end

      req
      |> Keyword.merge(Provider.http_options(__MODULE__))
      |> Req.post()
      |> answer(model, timeout_ms)
    end
  end

  defp answer({:ok, %Req.Response{status: status, body: body}}, model, timeout_ms)
       when status in 200..299 do
    decoded = Provider.decode_body(body)
    url = image_url(decoded)

    cond do
      unsafe?(decoded) ->
        {:error, :refused}

      is_binary(url) and url != "" ->
        with {:ok, bytes} <- Provider.get_bytes(url, timeout_ms: timeout_ms, provider: __MODULE__) do
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

  defp image_url(decoded) do
    get_in(decoded, ["data", Access.at(0), "url"]) ||
      get_in(decoded, ["data", Access.at(0), "image_url"])
  end

  defp unsafe?(decoded) do
    case get_in(decoded, ["data", Access.at(0), "is_image_safe"]) do
      false -> true
      "false" -> true
      _ -> false
    end
  end

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
