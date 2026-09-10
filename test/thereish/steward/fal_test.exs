defmodule Thereish.Steward.FalTest do
  use Thereish.DataCase, async: false

  @moduletag :capture_log

  alias Thereish.Steward.Fal
  alias Thereish.Steward.Limner

  @png Limner.png("#c4a35a", 8)
  @data_uri "data:image/png;base64," <> Base.encode64(@png)

  describe "image generation" do
    test "returns PNG bytes from a sync data URI" do
      Req.Test.stub(Fal, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{"images" => [%{"url" => @data_uri}]})
        )
      end)

      assert {:ok, result} =
               Fal.generate(%{
                 prompt: Limner.prompt("Liminal spaces", "#c4a35a"),
                 api_key: "test-fal",
                 seed: 84,
                 size: 512
               })

      assert result.bytes == @png
      assert result.model == "fal-ai/flux/schnell"
    end

    test "NSFW flag is :refused, not a crash" do
      Req.Test.stub(Fal, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "images" => [%{"url" => @data_uri}],
            "has_nsfw_concepts" => [true]
          })
        )
      end)

      assert {:error, :refused} =
               Fal.generate(%{prompt: Limner.prompt("murder", "#7a1f1f"), api_key: "test-fal"})
    end

    test "returns error when API key is missing" do
      assert {:error, :no_api_key} = Fal.generate(%{prompt: "lighthouse"})
    end
  end
end
