defmodule MeaningGame.Steward.ElevenLabsTest do
  use MeaningGame.DataCase, async: true

  @moduletag :capture_log

  alias MeaningGame.Steward.ElevenLabs

  @fake_mp3 <<255, 251, 144, 100, 0, 0, 0, 0, 0, 0, 0, 0>>

  describe "sound generation" do
    test "builds a request with text, duration, prompt influence and loop, and parses answer with character-cost" do
      test_pid = self()

      Req.Test.stub(ElevenLabs, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        send(
          test_pid,
          {:request, conn.method, conn.request_path, conn.query_string, conn.req_headers, decoded}
        )

        conn
        |> Plug.Conn.put_resp_header("content-type", "audio/mpeg")
        |> Plug.Conn.put_resp_header("character-cost", "150")
        |> Plug.Conn.send_resp(200, @fake_mp3)
      end)

      request = %{
        text: "A rising 2.5 second beat resolving on the downbeat",
        duration_seconds: 2.5,
        prompt_influence: 0.4,
        loop: false,
        output_format: "mp3_44100_128",
        model: "eleven_text_to_sound_v2",
        api_key: "test-xi-key",
        timeout_ms: 5_000
      }

      assert {:ok, response} = ElevenLabs.generate(request)

      assert response.bytes == @fake_mp3
      assert response.model == "eleven_text_to_sound_v2"
      assert response.character_cost == 150
      assert response.cost_usd > 0

      assert_receive {:request, "POST", "/v1/sound-generation", query, headers, body}
      assert query =~ "output_format=mp3_44100_128"
      assert {"xi-api-key", "test-xi-key"} in headers
      assert body["text"] == "A rising 2.5 second beat resolving on the downbeat"
      assert body["duration_seconds"] == 2.5
      assert body["prompt_influence"] == 0.4
      refute Map.has_key?(body, "loop")
    end

    test "includes loop in request body when loop is true" do
      test_pid = self()

      Req.Test.stub(ElevenLabs, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:body, Jason.decode!(body)})

        conn
        |> Plug.Conn.put_resp_header("content-type", "audio/mpeg")
        |> Plug.Conn.send_resp(200, @fake_mp3)
      end)

      request = %{
        text: "An ambient room tone loop",
        loop: true,
        api_key: "test-key"
      }

      assert {:ok, _} = ElevenLabs.generate(request)
      assert_receive {:body, %{"loop" => true}}
    end

    test "parses a recorded error response" do
      Req.Test.stub(ElevenLabs, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(
          400,
          Jason.encode!(%{"detail" => %{"message" => "Quota exceeded"}})
        )
      end)

      request = %{text: "fail", api_key: "test-key"}

      assert {:error, {:http, 400, %{"detail" => %{"message" => "Quota exceeded"}}}} =
               ElevenLabs.generate(request)
    end

    test "returns error when API key is missing" do
      assert {:error, :no_api_key} = ElevenLabs.generate(%{text: "no key", api_key: nil})
      assert {:error, :no_api_key} = ElevenLabs.generate(%{text: "empty key", api_key: ""})
    end

    @tag :live
    test "live sound generation smoke test" do
      MeaningGame.StewardFixtures.let_it_call_eleven_labs()
      key = System.fetch_env!("ELEVENLABS_API_KEY")

      assert {:ok, res} =
               ElevenLabs.generate(%{
                 text: "A soft bell chime",
                 duration_seconds: 1.0,
                 api_key: key
               })

      assert byte_size(res.bytes) > 0
      assert res.cost_usd > 0
    end
  end
end
