defmodule Thereish.Steward.BflTest do
  use Thereish.DataCase, async: false

  @moduletag :capture_log

  alias Thereish.Steward.Bfl
  alias Thereish.Steward.Limner

  @png Limner.png("#d8c8a0", 8)

  describe "image generation" do
    test "submits, polls Ready, and downloads the sample" do
      poll_count = Agent.start_link(fn -> 0 end) |> elem(1)

      Req.Test.stub(Bfl, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/v1/flux-2-flex"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(
              200,
              Jason.encode!(%{
                "id" => "task_1",
                "polling_url" => "https://api.bfl.ai/v1/get_result?id=task_1"
              })
            )

          {"GET", "/v1/get_result"} ->
            step = Agent.get_and_update(poll_count, &{&1 + 1, &1 + 1})

            payload =
              if step == 1 do
                %{"status" => "Pending"}
              else
                %{
                  "status" => "Ready",
                  "result" => %{"sample" => "https://cdn.bfl.ai/sample.png"}
                }
              end

            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(payload))

          {"GET", "/sample.png"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "image/png")
            |> Plug.Conn.send_resp(200, @png)
        end
      end)

      assert {:ok, result} =
               Bfl.generate(%{
                 prompt: Limner.prompt("lighthouse", "#d8c8a0"),
                 api_key: "test-bfl",
                 seed: 84,
                 size: 512,
                 poll_interval_ms: 5,
                 deadline_ms: 2_000
               })

      assert result.bytes == @png
      assert result.model == "flux-2-flex"
      assert result.cost_usd == 512 * 512 / 1_000_000 * 0.05
    end

    test "a moderated Give is :refused, not a crash" do
      Req.Test.stub(Bfl, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/v1/flux-2-flex"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(
              200,
              Jason.encode!(%{
                "id" => "task_mod",
                "polling_url" => "https://api.bfl.ai/v1/get_result?id=task_mod"
              })
            )

          {"GET", "/v1/get_result"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"status" => "Content Moderated"}))
        end
      end)

      assert {:error, :refused} =
               Bfl.generate(%{
                 prompt: Limner.prompt("murder", "#7a1f1f"),
                 api_key: "test-bfl",
                 poll_interval_ms: 5,
                 deadline_ms: 1_000
               })
    end

    test "returns error when API key is missing" do
      assert {:error, :no_api_key} = Bfl.generate(%{prompt: "lighthouse"})
    end

    @tag :live
    test "live BFL FLUX.2 smoke test" do
      Thereish.StewardFixtures.let_it_call_bfl()
      key = System.get_env("BLACK_FOREST_LABS_API_KEY") || System.fetch_env!("BFL_API_KEY")

      assert {:ok, res} =
               Bfl.generate(%{
                 prompt: Limner.prompt("lighthouse", "#d8c8a0"),
                 api_key: key,
                 seed: 84,
                 size: 512,
                 deadline_ms: 60_000
               })

      assert byte_size(res.bytes) > 0
    end
  end
end
