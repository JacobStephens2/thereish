defmodule Thereish.Steward.LyriaTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Thereish.Steward.Lyria

  @fake_mp3 <<255, 251, 144, 100, 1, 2, 3, 4>>

  defp song(bytes) do
    %{
      "candidates" => [
        %{
          "content" => %{
            "role" => "model",
            "parts" => [
              %{"text" => "[[A0]]\n[[B1]]"},
              %{"inlineData" => %{"mimeType" => "audio/mpeg", "data" => Base.encode64(bytes)}}
            ]
          },
          "finishReason" => "STOP"
        }
      ],
      "modelVersion" => "lyria-3.5"
    }
  end

  defp reply(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  describe "instrumental music generation" do
    test "asks the model for the prompt and answers the song's MP3 bytes at the model's price" do
      test_pid = self()

      Req.Test.stub(Lyria, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        send(
          test_pid,
          {:called, conn.method, conn.request_path, conn.req_headers, Jason.decode!(body)}
        )

        reply(conn, 200, song(@fake_mp3))
      end)

      assert {:ok, result} =
               Lyria.generate(%{
                 prompt: "Instrumental music. Gives: pine, cold river",
                 model: "lyria-3.5",
                 api_key: "test-gemini-key",
                 deadline_ms: 2_000
               })

      assert result.bytes == @fake_mp3
      assert result.model == "lyria-3.5"
      assert result.cost_usd == 0.08

      assert_receive {:called, "POST", "/v1beta/models/lyria-3.5:generateContent", headers, body}
      assert {"x-goog-api-key", "test-gemini-key"} in headers

      assert [%{"role" => "user", "parts" => [%{"text" => text}]}] = body["contents"]
      assert String.starts_with?(text, "Instrumental music. Gives: pine, cold river")
    end

    test "asks for no vocals, since Lyria has no instrumental switch" do
      test_pid = self()

      Req.Test.stub(Lyria, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:body, Jason.decode!(body)})
        reply(conn, 200, song(@fake_mp3))
      end)

      Lyria.generate(%{prompt: "Instrumental music. Gives: surf rock", api_key: "k"})

      assert_receive {:body, %{"contents" => [%{"parts" => [%{"text" => text}]}]}}
      assert text =~ "No vocals, no singing, no speech, no shouts."
    end

    test "a quota refusal is an error, not a track" do
      Req.Test.stub(Lyria, fn conn ->
        reply(conn, 429, %{
          "error" => %{
            "code" => 429,
            "status" => "RESOURCE_EXHAUSTED",
            "message" => "Quota exceeded"
          }
        })
      end)

      assert {:error, {:http, 429, %{"error" => %{"status" => "RESOURCE_EXHAUSTED"}}}} =
               Lyria.generate(%{prompt: "music", model: "lyria-3.5", api_key: "k"})
    end

    test "an answer with no audio is asked for once more" do
      calls = Agent.start_link(fn -> 0 end) |> elem(1)

      Req.Test.stub(Lyria, fn conn ->
        case Agent.get_and_update(calls, &{&1 + 1, &1 + 1}) do
          1 -> reply(conn, 200, %{"promptFeedback" => %{"blockReason" => "PROHIBITED_CONTENT"}})
          _ -> reply(conn, 200, song(@fake_mp3))
        end
      end)

      assert {:ok, %{bytes: @fake_mp3}} =
               Lyria.generate(%{prompt: "music", model: "lyria-3.5", api_key: "k"})

      assert Agent.get(calls, & &1) == 2
    end

    test "an answer with no audio twice is an error" do
      Req.Test.stub(Lyria, fn conn ->
        reply(conn, 200, %{"promptFeedback" => %{"blockReason" => "OTHER"}})
      end)

      assert {:error, {:no_audio, %{"promptFeedback" => _}}} =
               Lyria.generate(%{prompt: "music", model: "lyria-3.5", api_key: "k"})
    end

    test "returns error when API key is missing" do
      assert {:error, :no_api_key} = Lyria.generate(%{prompt: "music", api_key: nil})
      assert {:error, :no_api_key} = Lyria.generate(%{prompt: "music", api_key: ""})
    end

    @tag :live
    test "live music generation smoke test" do
      Thereish.StewardFixtures.let_it_call_lyria()

      assert {:ok, res} =
               Lyria.generate(%{
                 prompt: "Instrumental music. Gives: warm acoustic guitar",
                 model: "lyria-3-clip-preview",
                 api_key: System.fetch_env!("GEMINI_API_KEY"),
                 deadline_ms: 180_000
               })

      assert byte_size(res.bytes) > 0
      assert res.cost_usd > 0
    end
  end
end
