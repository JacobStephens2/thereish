defmodule Thereish.Steward.ApiframeTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias Thereish.Steward.Apiframe

  @fake_mp3 <<255, 251, 144, 100, 9, 8, 7>>

  defp reply(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  defp request(overrides \\ %{}) do
    Map.merge(
      %{
        prompt: "Instrumental music. Gives: surf rock, a tax audit",
        model: "V5_5",
        api_key: "test-apiframe-key",
        deadline_ms: 2_000,
        poll_interval_ms: 5
      },
      overrides
    )
  end

  describe "instrumental music generation" do
    test "submits an instrumental Suno job, polls it to completion, and downloads the first track" do
      polls = Agent.start_link(fn -> 0 end) |> elem(1)
      test_pid = self()

      Req.Test.stub(Apiframe, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/v2/music/generate"} ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            send(test_pid, {:submitted, conn.req_headers, Jason.decode!(body)})
            reply(conn, 200, %{"jobId" => "job-1", "status" => "QUEUED"})

          {"GET", "/v2/jobs/job-1"} ->
            case Agent.get_and_update(polls, &{&1 + 1, &1 + 1}) do
              1 ->
                reply(conn, 200, %{"id" => "job-1", "status" => "PROCESSING", "result" => nil})

              _ ->
                reply(conn, 200, %{
                  "id" => "job-1",
                  "status" => "COMPLETED",
                  "result" => %{
                    "tracks" => [
                      %{
                        "title" => "Audit Wave",
                        "audioUrl" => "https://cdn2.apiframe.ai/audio/a.mp3",
                        "duration" => 152.8
                      },
                      %{
                        "title" => "Audit Wave",
                        "audioUrl" => "https://cdn2.apiframe.ai/audio/b.mp3",
                        "duration" => 129.6
                      }
                    ]
                  }
                })
            end

          {"GET", "/audio/a.mp3"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "audio/mpeg")
            |> Plug.Conn.send_resp(200, @fake_mp3)
        end
      end)

      assert {:ok, result} = Apiframe.generate(request())

      assert result.bytes == @fake_mp3
      assert result.url == "https://cdn2.apiframe.ai/audio/a.mp3"
      assert result.duration == 153
      assert result.model == "V5_5"
      assert result.cost_usd == 0.11

      assert_receive {:submitted, headers, body}
      assert {"x-api-key", "test-apiframe-key"} in headers
      assert body["model"] == "suno"
      assert body["prompt"] == "Instrumental music. Gives: surf rock, a tax audit"
      assert body["sunoParams"] == %{"model_version" => "V5_5", "instrumental" => true}
    end

    test "a prompt over Suno's 500 characters is cut to fit" do
      test_pid = self()

      Req.Test.stub(Apiframe, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:submitted, Jason.decode!(body)})
        reply(conn, 429, %{"error" => "Too many requests"})
      end)

      Apiframe.generate(request(%{prompt: String.duplicate("é", 600)}))

      assert_receive {:submitted, %{"prompt" => prompt}}
      assert String.length(prompt) == 500
    end

    test "a quota refusal on submit is an error, not a track" do
      Req.Test.stub(Apiframe, fn conn ->
        reply(conn, 402, %{"error" => "Insufficient credits"})
      end)

      assert {:error, {:http, 402, %{"error" => "Insufficient credits"}}} =
               Apiframe.generate(request())
    end

    test "a failed job is an error" do
      Req.Test.stub(Apiframe, fn conn ->
        case conn.method do
          "POST" ->
            reply(conn, 200, %{"jobId" => "job-2", "status" => "QUEUED"})

          "GET" ->
            reply(conn, 200, %{"id" => "job-2", "status" => "FAILED", "error" => "moderated"})
        end
      end)

      assert {:error, {:failed, "moderated"}} = Apiframe.generate(request())
    end

    test "a job still running at the deadline is a timeout" do
      Req.Test.stub(Apiframe, fn conn ->
        case conn.method do
          "POST" -> reply(conn, 200, %{"jobId" => "job-3", "status" => "QUEUED"})
          "GET" -> reply(conn, 200, %{"id" => "job-3", "status" => "PROCESSING"})
        end
      end)

      assert {:error, :timeout} =
               Apiframe.generate(request(%{deadline_ms: 30, poll_interval_ms: 10}))
    end

    test "returns error when API key is missing" do
      assert {:error, :no_api_key} = Apiframe.generate(request(%{api_key: nil}))
      assert {:error, :no_api_key} = Apiframe.generate(request(%{api_key: ""}))
    end

    @tag :live
    test "live music generation smoke test" do
      Thereish.StewardFixtures.let_it_call_apiframe()

      assert {:ok, res} =
               Apiframe.generate(%{
                 prompt: "Instrumental music. Gives: warm acoustic guitar",
                 model: "V5_5",
                 api_key: System.fetch_env!("APIFRAME_API_KEY"),
                 deadline_ms: 180_000
               })

      assert byte_size(res.bytes) > 0
      assert res.cost_usd > 0
    end
  end
end
