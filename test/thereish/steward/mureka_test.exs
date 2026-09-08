defmodule Thereish.Steward.MurekaTest do
  use Thereish.DataCase, async: false

  @moduletag :capture_log

  alias Thereish.Steward.Mureka

  @fake_mp3 <<255, 251, 144, 100, 1, 2, 3, 4>>

  describe "instrumental music generation" do
    test "starts a job, polls preparing -> running -> succeeded, and downloads the chosen URL" do
      poll_count = Agent.start_link(fn -> 0 end) |> elem(1)
      test_pid = self()

      Req.Test.stub(Mureka, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/v1/instrumental/generate"} ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            decoded = Jason.decode!(body)
            send(test_pid, {:generate_called, conn.req_headers, decoded})

            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"id" => "task_abc123"}))

          {"GET", "/v1/instrumental/query/task_abc123"} ->
            step = Agent.get_and_update(poll_count, &{&1 + 1, &1 + 1})

            status =
              case step do
                1 -> "preparing"
                2 -> "running"
                _ -> "succeeded"
              end

            response_data =
              if status == "succeeded" do
                %{
                  "id" => "task_abc123",
                  "status" => status,
                  "choices" => [%{"url" => "https://cdn.mureka.ai/audio/track_abc.mp3"}]
                }
              else
                %{"id" => "task_abc123", "status" => status}
              end

            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(response_data))

          {"GET", "/audio/track_abc.mp3"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "audio/mpeg")
            |> Plug.Conn.send_resp(200, @fake_mp3)
        end
      end)

      request = %{
        prompt: "A slow acoustic guitar melody that sits under conversation",
        model: "auto",
        n: 1,
        api_key: "test-mureka-key",
        deadline_ms: 2_000,
        poll_interval_ms: 5
      }

      assert {:ok, result} = Mureka.generate(request)

      assert result.bytes == @fake_mp3
      assert result.url == "https://cdn.mureka.ai/audio/track_abc.mp3"
      assert result.model == "auto"
      assert result.cost_usd == 0.04

      assert_receive {:generate_called, headers, body}
      assert {"authorization", "Bearer test-mureka-key"} in headers
      assert body["model"] == "auto"
      assert body["prompt"] == "A slow acoustic guitar melody that sits under conversation"
      assert body["n"] == 1
    end

    test "starts a job with stream: true, polls until stream_url is returned during streaming phase" do
      poll_count = Agent.start_link(fn -> 0 end) |> elem(1)
      test_pid = self()

      Req.Test.stub(Mureka, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/v1/instrumental/generate"} ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            decoded = Jason.decode!(body)
            send(test_pid, {:generate_stream_called, conn.req_headers, decoded})

            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"id" => "task_stream123"}))

          {"GET", "/v1/instrumental/query/task_stream123"} ->
            step = Agent.get_and_update(poll_count, &{&1 + 1, &1 + 1})

            response_data =
              case step do
                1 ->
                  %{"id" => "task_stream123", "status" => "preparing"}

                2 ->
                  %{
                    "id" => "task_stream123",
                    "status" => "streaming",
                    "stream_url" => "https://stream.mureka.ai/live/task_stream123.mp3",
                    "choices" => [
                      %{"stream_url" => "https://stream.mureka.ai/live/task_stream123.mp3"}
                    ]
                  }

                _ ->
                  %{
                    "id" => "task_stream123",
                    "status" => "succeeded",
                    "choices" => [%{"url" => "https://cdn.mureka.ai/audio/final.mp3"}]
                  }
              end

            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(response_data))
        end
      end)

      request = %{
        prompt: "Fast atmospheric synth pad",
        model: "auto",
        api_key: "test-mureka-key",
        deadline_ms: 2_000,
        poll_interval_ms: 5
      }

      assert {:ok, result} = Mureka.stream(request)

      assert result.stream_url == "https://stream.mureka.ai/live/task_stream123.mp3"
      assert result.status == "streaming"
      assert result.task_id == "task_stream123"
      assert is_integer(result.time_to_stream_ms)
      assert result.time_to_stream_ms >= 0

      assert_receive {:generate_stream_called, headers, body}
      assert {"authorization", "Bearer test-mureka-key"} in headers
      assert body["stream"] == true
      assert body["prompt"] == "Fast atmospheric synth pad"
    end

    test "stream_generate calls on_stream callback when streaming, then downloads final MP3 on succeeded" do
      poll_count = Agent.start_link(fn -> 0 end) |> elem(1)
      test_pid = self()

      Req.Test.stub(Mureka, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/v1/instrumental/generate"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"id" => "task_sg123"}))

          {"GET", "/v1/instrumental/query/task_sg123"} ->
            step = Agent.get_and_update(poll_count, &{&1 + 1, &1 + 1})

            response_data =
              case step do
                1 ->
                  %{
                    "id" => "task_sg123",
                    "status" => "streaming",
                    "stream_url" => "https://stream.mureka.ai/live/sg123.aac",
                    "choices" => [%{"stream_url" => "https://stream.mureka.ai/live/sg123.aac"}]
                  }

                _ ->
                  %{
                    "id" => "task_sg123",
                    "status" => "succeeded",
                    "choices" => [%{"url" => "https://cdn.mureka.ai/audio/final_sg.mp3"}]
                  }
              end

            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(response_data))

          {"GET", "/audio/final_sg.mp3"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "audio/mpeg")
            |> Plug.Conn.send_resp(200, @fake_mp3)
        end
      end)

      request = %{
        prompt: "Flowing stream instrumental",
        api_key: "test-mureka-key",
        deadline_ms: 2_000,
        poll_interval_ms: 5
      }

      on_stream = fn info ->
        send(test_pid, {:stream_callback_received, info})
      end

      assert {:ok, result} = Mureka.stream_generate(request, on_stream)

      assert result.bytes == @fake_mp3
      assert result.url == "https://cdn.mureka.ai/audio/final_sg.mp3"
      assert result.cost_usd == 0.04

      assert_receive {:stream_callback_received, stream_info}
      assert stream_info.stream_url == "https://stream.mureka.ai/live/sg123.aac"
      assert stream_info.task_id == "task_sg123"
    end

    test "handles job failure" do
      Req.Test.stub(Mureka, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/v1/instrumental/generate"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"id" => "task_failed"}))

          {"GET", "/v1/instrumental/query/task_failed"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(
              200,
              Jason.encode!(%{"id" => "task_failed", "status" => "failed"})
            )
        end
      end)

      request = %{
        prompt: "Will fail",
        api_key: "test-key",
        deadline_ms: 1_000,
        poll_interval_ms: 5
      }

      assert {:error, {:failed, "failed"}} = Mureka.generate(request)
    end

    test "handles expired deadline" do
      Req.Test.stub(Mureka, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/v1/instrumental/generate"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"id" => "task_stuck"}))

          {"GET", "/v1/instrumental/query/task_stuck"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(
              200,
              Jason.encode!(%{"id" => "task_stuck", "status" => "running"})
            )
        end
      end)

      request = %{
        prompt: "Stuck in queue",
        api_key: "test-key",
        deadline_ms: 30,
        poll_interval_ms: 10
      }

      assert {:error, :timeout} = Mureka.generate(request)
    end

    test "returns error when API key is missing" do
      assert {:error, :no_api_key} = Mureka.generate(%{prompt: "music", api_key: nil})
      assert {:error, :no_api_key} = Mureka.generate(%{prompt: "music", api_key: ""})
    end

    @tag :live
    test "live music generation smoke test" do
      Thereish.StewardFixtures.let_it_call_mureka()
      key = System.fetch_env!("MUREKA_API_KEY")

      assert {:ok, res} =
               Mureka.generate(%{
                 prompt: "Warm acoustic guitar loop",
                 n: 1,
                 api_key: key,
                 deadline_ms: 180_000
               })

      assert byte_size(res.bytes) > 0
      assert res.cost_usd > 0
    end
  end
end
