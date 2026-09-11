defmodule Thereish.Steward.RecraftTest do
  use Thereish.DataCase, async: false

  @moduletag :capture_log

  alias Thereish.Steward.Limner
  alias Thereish.Steward.Recraft

  @png Limner.png("#c45c26", 8)
  @b64 Base.encode64(@png)

  describe "image generation" do
    test "returns PNG bytes from a b64_json response" do
      Req.Test.stub(Recraft, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{"data" => [%{"b64_json" => @b64}]})
        )
      end)

      assert {:ok, result} =
               Recraft.generate(%{
                 prompt: Limner.prompt("lighthouse", "#c45c26"),
                 api_key: "test-recraft",
                 model: "recraftv4"
               })

      assert result.bytes == @png
      assert result.format == :png
      assert result.model == "recraftv4"
      assert result.cost_usd == 0.04
    end

    test "a content-policy refusal is :refused, not a crash" do
      Req.Test.stub(Recraft, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(
          400,
          Jason.encode!(%{"message" => "Content policy violation: unsafe prompt"})
        )
      end)

      assert {:error, :refused} =
               Recraft.generate(%{
                 prompt: Limner.prompt("murder", "#7a1f1f"),
                 api_key: "test-recraft"
               })
    end

    test "returns error when API key is missing" do
      assert {:error, :no_api_key} = Recraft.generate(%{prompt: "lighthouse", api_key: nil})
      assert {:error, :no_api_key} = Recraft.generate(%{prompt: "lighthouse"})
    end

    test "style references are posted as multipart, not a urlencoded form" do
      test_pid = self()

      Req.Test.stub(Recraft, fn conn ->
        content_type = conn |> Plug.Conn.get_req_header("content-type") |> List.first()
        send(test_pid, {:recraft_content_type, content_type})

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{"data" => [%{"b64_json" => @b64}]})
        )
      end)

      assert {:ok, result} =
               Recraft.generate(%{
                 prompt: Limner.prompt("lighthouse", "#c45c26"),
                 api_key: "test-recraft",
                 model: "recraftv4_styles",
                 references: [@png]
               })

      assert_received {:recraft_content_type, content_type}
      assert content_type =~ "multipart/form-data"
      assert result.bytes == @png
    end

    @tag :live
    test "live Recraft smoke test" do
      Thereish.StewardFixtures.let_it_call_recraft()

      key =
        System.get_env("RECRAFT_AI_API_KEY") || System.get_env("RECRAFT_API_TOKEN") ||
          System.fetch_env!("RECRAFT_API_KEY")

      assert {:ok, res} =
               Recraft.generate(%{
                 prompt: Limner.prompt("lighthouse", "#d8c8a0"),
                 api_key: key,
                 model: "recraftv4",
                 size: 512
               })

      assert byte_size(res.bytes) > 0
    end
  end
end
