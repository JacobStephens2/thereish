defmodule MeaningGame.StewardFixtures do
  @moduledoc """
  Recorded Assayer responses, and the plug that hands them back.

  The suite must never spend money and never depend on a provider being up, so
  `config/test.exs` puts `Req.Test` behind every HTTP call the Steward makes and
  a test that wants a particular answer records one here. What is recorded is
  the whole response body a chat-completions endpoint returns — the envelope as
  well as the answer — because the parts the Steward reads out of the envelope
  (which model actually answered, why it stopped, how many tokens it spent) are
  part of what these tests are checking.

  The one thing a recording cannot prove is that the real endpoint still answers
  in this shape. That is what the live smoke test is for, tagged `:live` and
  excluded from the default run.
  """

  import ExUnit.Assertions

  @doc """
  Puts a recorded response behind the Assayer's provider for this test.

  The function is handed the decoded request body as well as the connection,
  because most of these tests care which of the two orderings they are answering.
  """
  def recorded(answer) when is_function(answer, 2) do
    Req.Test.stub(MeaningGame.Steward.Gemini, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      answer.(conn, Jason.decode!(body))
    end)
  end

  @doc "One whole response, with `content` as the answer the model wrote."
  def response(content) do
    %{
      "object" => "chat.completion",
      "created" => 1_756_000_000,
      "model" => "gemini-3.8-flash",
      "choices" => [
        %{
          "index" => 0,
          "finish_reason" => "stop",
          "message" => %{"role" => "assistant", "content" => content}
        }
      ],
      # Gemini's compatibility layer leaves the thinking out of
      # `completion_tokens` and puts it into `total_tokens`, which is why the
      # two do not add up and why the Steward prices output as total − prompt.
      "usage" => %{
        "prompt_tokens" => 242,
        "completion_tokens" => 61,
        "total_tokens" => 411
      }
    }
  end

  @doc """
  A well-formed verdict, as the model writes it: a JSON object in a string.

  `furthest` defaults to the pair the couch's tests grade, because almost every
  recording here is about something other than the carry-forward and an answer
  whose furthest pair is not two of the request's Bridges is rejected by the
  validator (ADR-0010).
  """
  def verdict(opts \\ []) do
    Jason.encode!(%{
      "reasoning" => Keyword.get(opts, :reasoning, "Both words name a marker left to be found."),
      "closeness" => Keyword.get(opts, :closeness, 80),
      "furthest" => Keyword.get(opts, :furthest, ["beacon", "cairn"]),
      "quip" => Keyword.get(opts, :quip, "One of you built it, the other lit it. Same errand.")
    })
  end

  @doc "A well-formed quip JSON string, as the model writes it on a Precedent hit."
  def quip_json(quip_text \\ "A fresh joke about tonight's words.") do
    Jason.encode!(%{"quip" => quip_text})
  end

  @doc "One whole response containing a quip JSON."
  def quip_response(quip_text \\ "A fresh joke about tonight's words.") do
    response(quip_json(quip_text))
  end

  @doc """
  Which of `bridges` this request asked about first, which is what tells the two
  orderings apart.

  Whichever Bridge the request names earliest is the one it put first. That is a
  property of the request rather than of the prompt's wording, so rewording the
  Assayer's question — which the couple's calibration will do — does not break
  every test here.
  """
  def first_bridge(body, bridges) do
    [%{"content" => user}] = Enum.filter(body["messages"], &(&1["role"] == "user"))

    Enum.min_by(bridges, fn bridge ->
      case :binary.match(user, bridge) do
        {at, _length} -> at
        :nomatch -> flunk("the request did not mention #{bridge} at all:\n#{user}")
      end
    end)
  end

  @doc """
  How many times this ordering has been asked, counting from one.

  Hedging means two identical requests arrive at once, and telling them apart is
  the whole point of the test that watches the first one win.
  """
  def asked(counts, ordering) do
    Agent.get_and_update(counts, fn seen ->
      {Map.get(seen, ordering, 0) + 1, Map.update(seen, ordering, 1, &(&1 + 1))}
    end)
  end

  @doc "A counter of how many times each ordering has been asked."
  def counts do
    {:ok, counts} = Agent.start_link(fn -> %{} end)

    counts
  end

  @doc """
  Holds an answer back until `wanted` requests for this ordering have arrived.

  What makes hedging hedging is that both requests are in flight at once, and a
  test that answered the first one immediately would be asserting on whether the
  second had got out of the gate yet.
  """
  def once_asked(counts, ordering, wanted, deadline \\ 1_000)

  def once_asked(_counts, ordering, wanted, deadline) when deadline <= 0 do
    flunk("only one request for #{ordering} arrived; expected #{wanted}")
  end

  def once_asked(counts, ordering, wanted, deadline) do
    if Agent.get(counts, &Map.get(&1, ordering, 0)) >= wanted do
      :ok
    else
      Process.sleep(5)
      once_asked(counts, ordering, wanted, deadline - 5)
    end
  end

  @doc """
  Changes what answers the Assayer for one test — how many identical requests,
  how many retries, how long it waits.

  Configuration is global, so a test that reaches for this cannot be async.
  """
  def assayer(opts) do
    steward = Application.fetch_env!(:meaning_game, :steward)
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:meaning_game, :steward, steward) end)

    {top, role_opts} = Keyword.split(opts, [:adapter])
    steward = Keyword.merge(steward, top)
    assayer = Keyword.merge(steward[:roles][:assayer], role_opts)

    Application.put_env(:meaning_game, :steward, put_in(steward[:roles][:assayer], assayer))
  end

  @doc """
  Puts the live Assayer behind the seam and takes the recorded responses out of
  its way, for the smoke tests that are meant to call somebody.

  Every other test is fenced off from the network by `config/test.exs`, so this
  is the only way through and it is deliberately noisy to read.
  """
  def let_it_call_the_provider do
    steward = Application.fetch_env!(:meaning_game, :steward)
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:meaning_game, :steward, steward) end)

    key =
      System.get_env("GEMINI_API_KEY") ||
        flunk("this test calls a provider and needs GEMINI_API_KEY in the environment")

    live =
      steward
      |> Keyword.put(:adapter, MeaningGame.Steward.Live)
      |> Keyword.put(:http_options, [])
      |> put_in([:roles, :assayer, :api_key], key)
      |> put_in([:roles, :assayer, :timeout_ms], 5_000)
      |> put_in([:roles, :assayer, :deadline_ms], 10_000)
      |> put_in([:roles, :author, :api_key], key)
      |> put_in([:roles, :scribe, :jobs, :naming, :api_key], key)
      |> put_in([:roles, :scribe, :jobs, :naming, :timeout_ms], 5_000)
      |> put_in([:roles, :scribe, :jobs, :naming, :deadline_ms], 10_000)

    Application.put_env(:meaning_game, :steward, live)
  end

  @doc """
  Puts the live Scribe behind the seam and takes the recorded responses out of
  its way, for the smoke test that is meant to call somebody.
  """
  def let_it_call_anthropic do
    steward = Application.fetch_env!(:meaning_game, :steward)
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:meaning_game, :steward, steward) end)

    key =
      System.get_env("ANTHROPIC_API_KEY") ||
        flunk("this test calls a provider and needs ANTHROPIC_API_KEY in the environment")

    live =
      steward
      |> Keyword.put(:adapter, MeaningGame.Steward.Live)
      |> Keyword.put(:http_options, [])
      |> put_in([:roles, :scribe, :jobs, :recap, :api_key], key)
      # The suite's Scribe answers in two seconds because it is a recording. A
      # model writing a real paragraph is given the couch's own budget.
      |> put_in([:roles, :scribe, :jobs, :recap, :timeout_ms], 120_000)
      |> put_in([:roles, :scribe, :jobs, :recap, :deadline_ms], 300_000)

    Application.put_env(:meaning_game, :steward, live)
  end

  @doc "Puts the real ElevenLabs provider behind the seam for the smoke test."
  def let_it_call_eleven_labs do
    steward = Application.fetch_env!(:meaning_game, :steward)
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:meaning_game, :steward, steward) end)

    key =
      System.get_env("ELEVENLABS_API_KEY") ||
        flunk("this test calls a provider and needs ELEVENLABS_API_KEY in the environment")

    live =
      steward
      |> Keyword.put(:adapter, MeaningGame.Steward.Live)
      |> Keyword.put(:http_options, [])
      |> put_in([:roles, :foley, :elevenlabs_api_key], key)
      |> put_in([:roles, :foley, :jobs, :effects, :api_key], key)
      |> put_in([:roles, :foley, :jobs, :voice, :provider], MeaningGame.Steward.ElevenLabs)
      |> put_in([:roles, :foley, :jobs, :voice, :voice_id], "JBFqnCBsd6RMkjVDRZzb")
      |> put_in([:roles, :foley, :jobs, :voice, :timeout_ms], 5_000)

    Application.put_env(:meaning_game, :steward, live)
  end

  @doc "Puts the real Mureka provider behind the seam for the smoke test."
  def let_it_call_mureka do
    steward = Application.fetch_env!(:meaning_game, :steward)
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:meaning_game, :steward, steward) end)

    key =
      System.get_env("MUREKA_API_KEY") ||
        flunk("this test calls a provider and needs MUREKA_API_KEY in the environment")

    live =
      steward
      |> Keyword.put(:http_options, [])
      |> put_in([:roles, :foley, :jobs, :music, :api_key], key)

    Application.put_env(:meaning_game, :steward, live)
  end

  @doc "Puts a recorded response behind the Author's provider for this test."
  def recorded_author(answer) when is_function(answer, 2) do
    Req.Test.stub(MeaningGame.Steward.Gemini, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      answer.(conn, Jason.decode!(body))
    end)
  end

  @doc "One whole response in Gemini chat completions shape."
  def author_response(content, opts \\ []) do
    finish_reason = Keyword.get(opts, :finish_reason, "stop")

    %{
      "object" => "chat.completion",
      "created" => 1_756_000_000,
      "model" => "gemini-3.8-flash",
      "choices" => [
        %{
          "index" => 0,
          "finish_reason" => finish_reason,
          "message" => %{"role" => "assistant", "content" => content}
        }
      ],
      "usage" => %{
        "prompt_tokens" => Keyword.get(opts, :input_tokens, 200),
        "completion_tokens" => Keyword.get(opts, :output_tokens, 50),
        "total_tokens" => Keyword.get(opts, :total_tokens, 250)
      }
    }
  end

  @doc "Puts a recorded response behind the Scribe's provider for this test."
  def recorded_scribe(answer) when is_function(answer, 2) do
    Req.Test.stub(MeaningGame.Steward.Anthropic, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      answer.(conn, Jason.decode!(body))
    end)
  end

  @doc "One whole response in Anthropic messages shape."
  def scribe_response(content, opts \\ []) do
    stop_reason = Keyword.get(opts, :stop_reason, "end_turn")

    %{
      "id" => "msg_test_scribe",
      "type" => "message",
      "role" => "assistant",
      "model" => "claude-fable-5-1",
      "content" => [
        %{"type" => "text", "text" => content}
      ],
      "stop_reason" => stop_reason,
      "usage" => %{
        "input_tokens" => Keyword.get(opts, :input_tokens, 450),
        "output_tokens" => Keyword.get(opts, :output_tokens, 350)
      }
    }
  end

  @doc """
  Puts the live Scribe behind the seam for one test, with a recorded provider
  behind that.

  Configuration is global, so a test that reaches for this cannot be async.
  """
  def live_scribe(job_opts \\ []) do
    steward = Application.fetch_env!(:meaning_game, :steward)
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:meaning_game, :steward, steward) end)

    recap = Keyword.merge(steward[:roles][:scribe][:jobs][:recap], job_opts)

    live =
      steward
      |> Keyword.put(:adapter, MeaningGame.Steward.Live)
      |> put_in([:roles, :scribe, :jobs, :recap, :api_key], "recorded-responses-need-no-key")
      |> put_in([:roles, :scribe, :jobs, :recap], recap)

    Application.put_env(:meaning_game, :steward, live)
  end

  @doc "A well-formed recap, as the Scribe writes it: a JSON object in a string."
  def written_recap(opts \\ []) do
    Jason.encode!(%{
      "recap" =>
        Keyword.get(
          opts,
          :recap,
          ~s(Jacob wrote "cairn" and Mara wrote "beacon", and they spent the evening ) <>
            ~s(circling the same lonely hill.)
        ),
      "callback" => Keyword.get(opts, :callback, "")
    })
  end

  @doc "A well-formed Author-3 JSON string."
  def author_json(opts \\ []) do
    Jason.encode!(%{
      "bookends" => Keyword.get(opts, :bookends, ["harbour", "cairn"]),
      "why" =>
        Keyword.get(
          opts,
          :why,
          "A coastal shelter stands far apart in meaning from a mountain monument."
        )
    })
  end

  @doc "Legacy alias for author_json."
  def authored_page_json(opts \\ []), do: author_json(opts)

  @doc """
  Puts the live Hume voice provider behind the seam for a live smoke test.
  """
  def let_it_call_hume do
    steward = Application.fetch_env!(:meaning_game, :steward)
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:meaning_game, :steward, steward) end)

    api_key =
      System.get_env("HUME_API_KEY") ||
        flunk("this test calls Hume and needs HUME_API_KEY in the environment")

    secret_key = System.get_env("HUME_SECRET_KEY")

    live =
      steward
      |> Keyword.put(:adapter, MeaningGame.Steward.Live)
      |> Keyword.put(:http_options, [])
      |> put_in([:roles, :foley, :hume_api_key], api_key)
      |> put_in([:roles, :foley, :hume_secret_key], secret_key)
      |> put_in([:roles, :foley, :jobs, :voice, :provider], MeaningGame.Steward.Hume)
      |> put_in(
        [:roles, :foley, :jobs, :voice, :voice_id],
        "44cb3a51-07b4-4934-83fd-9d9e8d363ce6"
      )
      |> put_in([:roles, :foley, :jobs, :voice, :timeout_ms], 5_000)

    Application.put_env(:meaning_game, :steward, live)
  end
end
