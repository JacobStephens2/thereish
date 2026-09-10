defmodule Thereish.Steward.IdeogramTest do
  use Thereish.DataCase, async: false

  @moduletag :capture_log

  alias Thereish.Steward.Ideogram
  alias Thereish.Steward.Limner

  @png Limner.png("#6b3a2a", 8)

  describe "image generation" do
    test "downloads the image URL and returns PNG bytes" do
      Req.Test.stub(Ideogram, fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/v1/ideogram-v3/generate"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(
              200,
              Jason.encode!(%{
                "data" => [%{"url" => "https://ideogram.ai/api/images/fake.png"}]
              })
            )

          {"GET", "/api/images/fake.png"} ->
            conn
            |> Plug.Conn.put_resp_header("content-type", "image/png")
            |> Plug.Conn.send_resp(200, @png)
        end
      end)

      assert {:ok, result} =
               Ideogram.generate(%{
                 prompt: Limner.prompt("Vecna", "#6b3a2a"),
                 api_key: "test-ideogram",
                 seed: 84
               })

      assert result.bytes == @png
      assert result.model == "ideogram-v3-turbo"
      assert result.cost_usd == 0.03
    end

    test "a content-policy refusal is :refused, not a crash" do
      Req.Test.stub(Ideogram, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(
          400,
          Jason.encode!(%{"error" => "Prompt was flagged by the safety filter"})
        )
      end)

      assert {:error, :refused} =
               Ideogram.generate(%{
                 prompt: Limner.prompt("murder", "#7a1f1f"),
                 api_key: "test-ideogram"
               })
    end

    test "an unsafe image flag is :refused" do
      Req.Test.stub(Ideogram, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "data" => [
              %{"url" => "https://ideogram.ai/api/images/fake.png", "is_image_safe" => false}
            ]
          })
        )
      end)

      assert {:error, :refused} =
               Ideogram.generate(%{prompt: "murder", api_key: "test-ideogram"})
    end

    test "returns error when API key is missing" do
      assert {:error, :no_api_key} = Ideogram.generate(%{prompt: "lighthouse"})
    end

    @tag :live
    test "live Ideogram smoke test" do
      Thereish.StewardFixtures.let_it_call_ideogram()
      key = System.fetch_env!("IDEOGRAM_API_KEY")

      assert {:ok, res} =
               Ideogram.generate(%{
                 prompt: Limner.prompt("lighthouse", "#d8c8a0"),
                 api_key: key,
                 seed: 84
               })

      assert byte_size(res.bytes) > 0
    end
  end
end
