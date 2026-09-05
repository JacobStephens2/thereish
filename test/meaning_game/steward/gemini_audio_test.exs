defmodule MeaningGame.Steward.GeminiAudioTest do
  use MeaningGame.DataCase, async: true

  @moduletag :capture_log

  alias MeaningGame.Steward.Gemini

  @clip_a <<1, 2, 3, 4>>
  @clip_b <<5, 6, 7, 8>>
  @clip_c <<9, 10, 11, 12>>

  describe "ranking audio clips with the ear" do
    test "sends N clips as inline audio parts with a brief and parses a ranking" do
      test_pid = self()
      clips = [@clip_a, @clip_b, @clip_c]

      Req.Test.stub(Gemini, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        send(test_pid, {:gemini_request, decoded})

        content =
          Jason.encode!(%{
            "ranking" => [
              %{"index" => 2, "reason" => "Candidate 2 resolves cleanly on the beat."},
              %{"index" => 1, "reason" => "Candidate 1 has good energy but slightly trailing."},
              %{"index" => 3, "reason" => "Candidate 3 is too faint."}
            ]
          })

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          "model" => "gemini-3.8-flash",
          "choices" => [
            %{"message" => %{"content" => content}, "finish_reason" => "stop"}
          ],
          "usage" => %{"prompt_tokens" => 300, "total_tokens" => 350}
        }))
      end)

      assert {:ok, ranking} =
               Gemini.rank(clips, "A 2.5 second beat figure resolving on the downbeat",
                 api_key: "test-gemini-key"
               )

      assert length(ranking) == 3
      assert Enum.map(ranking, & &1.index) == [2, 1, 3]
      assert hd(ranking).reason == "Candidate 2 resolves cleanly on the beat."

      assert_receive {:gemini_request, req}
      [_, %{"role" => "user", "content" => user_parts}] = req["messages"]

      # Verify brief text part exists
      assert Enum.any?(user_parts, &(&1["type"] == "text" && &1["text"] =~ "beat figure"))

      # Verify inline audio parts exist for each clip
      audio_parts = Enum.filter(user_parts, &(&1["type"] == "input_audio"))
      assert length(audio_parts) == 3
      assert Enum.at(audio_parts, 0)["input_audio"]["data"] == Base.encode64(@clip_a)
      assert Enum.at(audio_parts, 1)["input_audio"]["data"] == Base.encode64(@clip_b)
      assert Enum.at(audio_parts, 2)["input_audio"]["data"] == Base.encode64(@clip_c)
    end

    test "rejects an ordering that names an index it was not given" do
      clips = [@clip_a, @clip_b, @clip_c]

      Req.Test.stub(Gemini, fn conn ->
        content =
          Jason.encode!(%{
            "ranking" => [
              %{"index" => 5, "reason" => "Candidate 5 is great."},
              %{"index" => 1, "reason" => "Candidate 1 is okay."},
              %{"index" => 2, "reason" => "Candidate 2 is third."}
            ]
          })

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          "model" => "gemini-3.8-flash",
          "choices" => [%{"message" => %{"content" => content}}],
          "usage" => %{"prompt_tokens" => 100, "total_tokens" => 150}
        }))
      end)

      assert {:error, {:rejected, _why}} =
               Gemini.rank(clips, "Brief", api_key: "test-gemini-key")
    end

    test "rejects an ordering with duplicate or missing indices" do
      clips = [@clip_a, @clip_b, @clip_c]

      Req.Test.stub(Gemini, fn conn ->
        content =
          Jason.encode!(%{
            "ranking" => [
              %{"index" => 1, "reason" => "One."},
              %{"index" => 1, "reason" => "One again."},
              %{"index" => 2, "reason" => "Two."}
            ]
          })

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{
          "model" => "gemini-3.8-flash",
          "choices" => [%{"message" => %{"content" => content}}],
          "usage" => %{"prompt_tokens" => 100, "total_tokens" => 150}
        }))
      end)

      assert {:error, {:rejected, _why}} =
               Gemini.rank(clips, "Brief", api_key: "test-gemini-key")
    end

    @tag :live
    test "live gemini ear ranking smoke test" do
      MeaningGame.StewardFixtures.let_it_call_the_provider()
      key = System.fetch_env!("GEMINI_API_KEY")
      clip = <<255, 251, 144, 100, 0, 0, 0, 0, 0, 0, 0, 0>>

      assert {:ok, ranking} =
               Gemini.rank([clip, clip], "A soft bell chime", api_key: key)

      assert length(ranking) == 2
    end
  end
end
