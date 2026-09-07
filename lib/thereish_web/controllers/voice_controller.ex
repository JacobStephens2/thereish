defmodule ThereishWeb.VoiceController do
  @moduledoc """
  Serves synthesized voice audio for the Room's current Attempt.
  Answers 404 for any other Attempt or non-existent Room.
  """
  use ThereishWeb, :controller

  alias Thereish.Rooms

  def show(conn, %{"slug" => code, "attempt" => attempt_param}) do
    with {attempt, _} <- Integer.parse(attempt_param),
         {:ok, audio, format} <- Rooms.voice_audio(code, attempt) do
      content_type =
        case format do
          :mp3 -> "audio/mpeg"
          "mp3" -> "audio/mpeg"
          _ -> "application/octet-stream"
        end

      conn
      |> put_resp_content_type(content_type)
      |> send_resp(200, audio)
    else
      _ ->
        conn
        |> put_status(404)
        |> text("Not Found")
    end
  end
end
