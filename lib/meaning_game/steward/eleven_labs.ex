defmodule MeaningGame.Steward.ElevenLabs do
  @moduledoc """
  ElevenLabs text-to-speech provider.

  Uses v3 Conversational (`eleven_v3_conversational`) by default, outputting MP3
  at 44.1 kHz. Audio tags (such as `[laughs]`, `[whispers]`, `[sarcastic]`) are
  permitted inline in the spoken line. Character cost is read from the
  `character-cost` response header when present, falling back to string length.
  """
  require Logger

  alias MeaningGame.Steward.Provider

  @default_model "eleven_v3_conversational"
  @default_timeout_ms 3_000

  @doc """
  Synthesizes speech for one line of text via ElevenLabs TTS API.
  """
  @spec speak(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def speak(line, opts \\ []) do
    with {:ok, key} <- api_key(opts),
         {:ok, voice_id} <- fetch_voice_id(opts) do
      model = Keyword.get(opts, :model, @default_model)
      timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
      url = "https://api.elevenlabs.io/v1/text-to-speech/#{voice_id}"

      body = %{
        "text" => line,
        "model_id" => model
      }

      headers = [
        {"xi-api-key", key},
        {"content-type", "application/json"}
      ]

      req_opts =
        [
          url: url,
          params: [output_format: "mp3_44100_128"],
          headers: headers,
          json: body,
          receive_timeout: timeout,
          retry: false
        ]
        |> Keyword.merge(Provider.http_options(__MODULE__))

      case Req.post(req_opts) do
        {:ok, %Req.Response{status: 200, body: audio} = resp} when is_binary(audio) ->
          characters = parse_character_count(resp, line)
          cost_usd = Provider.character_cost(model, characters)

          {:ok,
           %{
             audio: audio,
             format: :mp3,
             meta: %{
               provider: __MODULE__,
               voice_id: voice_id,
               model: model,
               characters: characters,
               cost_usd: cost_usd
             }
           }}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, parse_error(status, body)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp parse_error(status, %{"detail" => %{"message" => message}}) when is_binary(message) do
    {:eleven_labs, status, message}
  end

  defp parse_error(status, %{"detail" => message}) when is_binary(message) do
    {:eleven_labs, status, message}
  end

  defp parse_error(status, %{"message" => message}) when is_binary(message) do
    {:eleven_labs, status, message}
  end

  defp parse_error(status, body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_error(status, decoded)
      _ -> {:http, status, body}
    end
  end

  defp parse_error(status, body), do: {:http, status, body}

  defp api_key(opts) do
    cond do
      Keyword.has_key?(opts, :api_key) ->
        case Keyword.get(opts, :api_key) do
          key when is_binary(key) and key != "" -> {:ok, key}
          _ -> {:error, :no_api_key}
        end

      Keyword.has_key?(opts, :elevenlabs_api_key) ->
        case Keyword.get(opts, :elevenlabs_api_key) do
          key when is_binary(key) and key != "" -> {:ok, key}
          _ -> {:error, :no_api_key}
        end

      true ->
        case config_key() do
          key when is_binary(key) and key != "" -> {:ok, key}
          _ -> {:error, :no_api_key}
        end
    end
  end

  defp fetch_voice_id(opts) do
    case Keyword.get(opts, :voice_id) do
      id when is_binary(id) and id != "" -> {:ok, id}
      _ -> {:ok, "JBFqnCBsd6RMkjVDRZzb"}
    end
  end

  defp config_key do
    try do
      role = MeaningGame.Steward.role(:foley, :voice)
      role[:elevenlabs_api_key] || role[:api_key]
    rescue
      _ -> nil
    end
  end

  defp parse_character_count(resp, line) do
    case Req.Response.get_header(resp, "character-cost") do
      [val | _] ->
        case Integer.parse(val) do
          {chars, _} -> chars
          :error -> String.length(line)
        end

      _ ->
        String.length(line)
    end
  end
end
