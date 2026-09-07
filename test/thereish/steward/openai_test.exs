defmodule Thereish.Steward.OpenAITest do
  use Thereish.DataCase, async: true

  @moduletag :capture_log

  alias Thereish.Steward.OpenAI

  describe "complete/1" do
    test "sends json_schema structured output and reasoning effort, parsing structured response and cost" do
      test_pid = self()

      Req.Test.stub(OpenAI, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        send(test_pid, {:request, conn.req_headers, decoded})

        response_body = %{
          "id" => "chatcmpl-test-01",
          "object" => "chat.completion",
          "created" => 1_756_000_000,
          "model" => "gpt-6-astra",
          "choices" => [
            %{
              "index" => 0,
              "finish_reason" => "stop",
              "message" => %{
                "role" => "assistant",
                "content" =>
                  Jason.encode!(%{
                    "bookends" => ["beacon", "harbour"],
                    "why" => "A high signal light contrasts with a sheltered coastal haven."
                  })
              }
            }
          ],
          "usage" => %{
            "prompt_tokens" => 200,
            "completion_tokens" => 50,
            "total_tokens" => 250
          }
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(response_body))
      end)

      schema = %{
        "type" => "object",
        "properties" => %{
          "bookends" => %{"type" => "array", "items" => %{"type" => "string"}},
          "why" => %{"type" => "string"}
        },
        "required" => ["bookends", "why"],
        "additionalProperties" => false
      }

      request = %{
        system: "You are the Author.",
        user: "Write two bookends.",
        schema: schema,
        schema_name: "authored_page",
        model: "gpt-6-astra",
        effort: "low",
        max_tokens: 400,
        timeout_ms: 5_000,
        api_key: "sk-test-openai-key"
      }

      assert {:ok, response} = OpenAI.complete(request)

      assert response.model == "gpt-6-astra"
      assert response.stop_reason == "stop"
      assert response.json["bookends"] == ["beacon", "harbour"]
      assert response.json["why"] =~ "sheltered coastal haven"
      assert is_float(response.cost_usd) and response.cost_usd > 0.0

      assert_receive {:request, headers, body}
      assert {"authorization", "Bearer sk-test-openai-key"} in headers
      assert body["model"] == "gpt-6-astra"
      assert body["reasoning_effort"] == "low"
      assert body["max_completion_tokens"] == 400
      assert body["response_format"]["type"] == "json_schema"
      assert body["response_format"]["json_schema"]["name"] == "authored_page"
      assert body["response_format"]["json_schema"]["strict"] == true
    end

    test "parses a recorded refusal cleanly" do
      Req.Test.stub(OpenAI, fn conn ->
        response_body = %{
          "id" => "chatcmpl-test-refusal",
          "object" => "chat.completion",
          "created" => 1_756_000_000,
          "model" => "gpt-6-astra",
          "choices" => [
            %{
              "index" => 0,
              "finish_reason" => "refusal",
              "message" => %{
                "role" => "assistant",
                "content" => nil,
                "refusal" => "I cannot write bookends for these settings."
              }
            }
          ],
          "usage" => %{
            "prompt_tokens" => 150,
            "completion_tokens" => 20,
            "total_tokens" => 170
          }
        }

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(response_body))
      end)

      request = %{
        system: "You are the Author.",
        user: "Settings: ...",
        schema: %{"type" => "object"},
        schema_name: "authored_page",
        model: "gpt-6-astra",
        effort: "low",
        max_tokens: 400,
        timeout_ms: 5_000,
        api_key: "sk-test-openai-key"
      }

      assert {:ok, response} = OpenAI.complete(request)
      assert response.model == "gpt-6-astra"
      assert response.json == nil
      assert response.stop_reason == "refusal"
      assert response[:refusal] == "I cannot write bookends for these settings."
      assert response.cost_usd > 0.0
    end

    test "returns :no_api_key when key is missing" do
      request = %{
        system: "You are the Author.",
        user: "Settings: ...",
        schema: %{},
        schema_name: "test",
        model: "gpt-6-astra",
        effort: "low",
        max_tokens: 400,
        timeout_ms: 5_000,
        api_key: nil
      }

      assert {:error, :no_api_key} = OpenAI.complete(request)
    end
  end
end
