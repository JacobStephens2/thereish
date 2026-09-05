defmodule MeaningGame.Steward.ElevenLabs do
  @moduledoc """
  ElevenLabs sound generation provider.

  Generates sound effects from text prompts using the `eleven_text_to_sound_v2` model.
  Returns audio bytes (MP3) and parses the `character-cost` header for spend tracking.
  """

  require Logger

  alias MeaningGame.Steward.Provider

  @url "https://api.elevenlabs.io/v1/sound-generation"

  @typedoc "A sound generation request"
  @type request :: %{
          required(:text) => String.t(),
          optional(:duration_seconds) => float() | nil,
          optional(:prompt_influence) => float() | nil,
          optional(:loop) => boolean(),
          optional(:output_format) => String.t(),
          optional(:model) => String.t(),
          optional(:api_key) => String.t() | nil,
          optional(:timeout_ms) => pos_integer()
        }

  @typedoc "A sound generation response"
  @type response :: %{
          bytes: binary(),
          model: String.t(),
          character_cost: non_neg_integer(),
          cost_usd: float()
        }

  @spec generate(request() | keyword() | map()) :: {:ok, response()} | {:error, term()}
  def generate(request) when is_list(request), do: request |> Map.new() |> generate()

  def generate(request) when is_map(request) do
    with {:ok, key} <- api_key(request) do
      model = Map.get(request, :model) || Map.get(request, "model", "eleven_text_to_sound_v2")
      output_format =
        Map.get(request, :output_format) ||
          Map.get(request, :format) ||
          Map.get(request, "output_format") ||
          Map.get(request, "format", "mp3_44100_128")
      timeout_ms = Map.get(request, :timeout_ms) || Map.get(request, "timeout_ms", 30_000)

      params = if output_format, do: [output_format: output_format], else: []

      [
        url: @url,
        params: params,
        headers: [{"xi-api-key", key}],
        json: body(request),
        receive_timeout: timeout_ms,
        retry: false
      ]
      |> Keyword.merge(Provider.http_options(__MODULE__))
      |> Req.post()
      |> answer(model)
    end
  end

  defp api_key(request) do
    case Map.get(request, :api_key) || Map.get(request, "api_key") do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ ->
        Logger.error("ELEVENLABS_API_KEY is not set; Foley cannot generate sound effects")
        {:error, :no_api_key}
    end
  end

  defp body(request) do
    text = Map.get(request, :text) || Map.get(request, "text")

    %{text: text}
    |> maybe_put(:duration_seconds, Map.get(request, :duration_seconds) || Map.get(request, "duration_seconds"))
    |> maybe_put(:prompt_influence, Map.get(request, :prompt_influence) || Map.get(request, "prompt_influence"))
    |> maybe_put_loop(Map.get(request, :loop) || Map.get(request, "loop"))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp maybe_put_loop(map, true), do: Map.put(map, :loop, true)
  defp maybe_put_loop(map, _), do: map

  defp answer({:ok, %Req.Response{status: 200, body: body, headers: headers}}, model) do
    character_cost = parse_character_cost(headers)

    {:ok,
     %{
       bytes: body,
       model: model,
       character_cost: character_cost,
       cost_usd: Provider.character_cost(model, character_cost)
     }}
  end

  defp answer({:ok, %Req.Response{status: status, body: body}}, _model) do
    {:error, {:http, status, Provider.decode_body(body)}}
  end

  defp answer({:error, reason}, _model), do: {:error, reason}

  defp parse_character_cost(headers) do
    Enum.find_value(headers, 0, fn {k, v} ->
      if String.downcase(to_string(k)) == "character-cost" do
        val = if is_list(v), do: List.first(v), else: v

        case Integer.parse(to_string(val)) do
          {int, _} -> int
          :error -> 0
        end
      end
    end)
  end
end
