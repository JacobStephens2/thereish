defmodule MeaningGame.Steward.Hume do
  @moduledoc """
  Hume Octave 2 text-to-speech provider.

  Uses Octave 2 (`version: "2"`) by default, outputting MP3 format. The response
  delivers base64-encoded audio within JSON, which is decoded into binary audio
  bytes. Character cost is computed based on input text length.
  """
  require Logger

  alias MeaningGame.Steward.Provider

  @default_model "octave-2"
  @default_timeout_ms 3_000
  @default_voice_id "44cb3a51-07b4-4934-83fd-9d9e8d363ce6"

  @doc """
  Synthesizes speech for one line of text via Hume TTS API.
  """
  @spec speak(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def speak(line, opts \\ []) do
    with {:ok, key} <- api_key(opts),
         {:ok, voice_id} <- fetch_voice_id(opts) do
      model = Keyword.get(opts, :model, @default_model)
      timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)

      url = "https://api.hume.ai/v0/tts"

      body = %{
        "utterances" => [
          %{
            "text" => line,
            "voice" => %{
              "id" => voice_id,
              "provider" => "HUME_AI"
            }
          }
        ],
        "format" => %{"type" => "mp3"},
        "num_generations" => 1,
        "version" => "2"
      }

      headers =
        [
          {"x-hume-api-key", key},
          {"content-type", "application/json"}
        ] ++
          case secret_key(opts) do
            {:ok, secret} -> [{"x-hume-secret-key", secret}]
            _ -> []
          end

      req_opts =
        [
          url: url,
          headers: headers,
          json: body,
          receive_timeout: timeout,
          retry: false
        ]
        |> Keyword.merge(Provider.http_options(__MODULE__))

      case Req.post(req_opts) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          parse_response(body, voice_id, model, line)

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, parse_error(status, body)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp parse_error(status, %{"message" => message}) when is_binary(message) do
    {:hume, status, message}
  end

  defp parse_error(status, %{"error" => message}) when is_binary(message) do
    {:hume, status, message}
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

      Keyword.has_key?(opts, :hume_api_key) ->
        case Keyword.get(opts, :hume_api_key) do
          key when is_binary(key) and key != "" -> {:ok, key}
          _ -> {:error, :no_api_key}
        end

      true ->
        case config_key(:hume_api_key) do
          key when is_binary(key) and key != "" -> {:ok, key}
          _ -> {:error, :no_api_key}
        end
    end
  end

  defp secret_key(opts) do
    key =
      case Keyword.get(opts, :secret_key) || Keyword.get(opts, :hume_secret_key) do
        k when is_binary(k) and k != "" -> k
        _ -> config_key(:hume_secret_key)
      end

    case key do
      k when is_binary(k) and k != "" -> {:ok, k}
      _ -> {:error, :no_secret_key}
    end
  end

  defp fetch_voice_id(opts) do
    case Keyword.get(opts, :voice_id) do
      id when is_binary(id) and id != "" -> {:ok, id}
      _ -> {:ok, @default_voice_id}
    end
  end

  defp config_key(field) do
    try do
      role = MeaningGame.Steward.role(:foley, :voice)
      role[field] || (field == :hume_api_key && role[:api_key])
    rescue
      _ -> nil
    end
  end

  defp parse_response(body, voice_id, model, line) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_response(decoded, voice_id, model, line)
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_response(%{"generations" => [%{"audio" => base64_audio} | _]}, voice_id, model, line) do
    case Base.decode64(base64_audio) do
      {:ok, audio} ->
        characters = String.length(line)
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

      :error ->
        {:error, :invalid_audio_base64}
    end
  end

  defp parse_response(other, _voice_id, _model, _line) do
    {:error, {:unexpected_hume_response, other}}
  end
end
