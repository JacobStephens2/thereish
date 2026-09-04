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

  @doc "A well-formed verdict, as the model writes it: a JSON object in a string."
  def verdict(opts \\ []) do
    Jason.encode!(%{
      "reasoning" => Keyword.get(opts, :reasoning, "Both words name a marker left to be found."),
      "closeness" => Keyword.get(opts, :closeness, 80),
      "quip" => Keyword.get(opts, :quip, "One of you built it, the other lit it. Same errand.")
    })
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

    Application.put_env(:meaning_game, :steward, live)
  end

  @doc "Puts a recorded response behind the Author's provider for this test."
  def recorded_author(answer) when is_function(answer, 2) do
    Req.Test.stub(MeaningGame.Steward.Anthropic, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      answer.(conn, Jason.decode!(body))
    end)
  end

  @doc "One whole response in Anthropic messages shape."
  def author_response(content, opts \\ []) do
    stop_reason = Keyword.get(opts, :stop_reason, "end_turn")

    %{
      "id" => "msg_test_author",
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

  @doc "A well-formed authored page JSON."
  def authored_page_json(opts \\ []) do
    Jason.encode!(%{
      "theme" => Keyword.get(opts, :theme, "suburban family life"),
      "anchors" => Keyword.get(opts, :anchors, ["backyard", "weekend"]),
      "bait" => Keyword.get(opts, :bait, "barbecue"),
      "deep_bridges" => Keyword.get(opts, :deep_bridges, ["lawnmower", "chores"]),
      "likely_bridges" =>
        Keyword.get(opts, :likely_bridges, ["barbecue", "lawnmower", "chores", "family", "party"]),
      "why_these" =>
        Keyword.get(
          opts,
          :why_these,
          "Backyard and weekend invite barbecue as the immediate trap."
        ),
      "band_scripts" =>
        Keyword.get(opts, :band_scripts, MeaningGame.Steward.Fake.default_band_scripts())
    })
  end
end
