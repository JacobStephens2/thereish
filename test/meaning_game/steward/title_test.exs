defmodule MeaningGame.Steward.TitleTest do
  use MeaningGame.DataCase, async: false

  @moduletag :capture_log

  import MeaningGame.StewardFixtures

  alias MeaningGame.Steward
  alias MeaningGame.Steward.Live
  alias MeaningGame.Steward.Title

  defp title_response(title) do
    response(Jason.encode!(%{"title" => title}))
  end

  defp live_title(role_opts \\ []) do
    steward = Application.fetch_env!(:meaning_game, :steward)
    on_exit(fn -> Application.put_env(:meaning_game, :steward, steward) end)

    title_job = Keyword.merge(steward[:roles][:scribe][:jobs][:title], role_opts)

    live =
      steward
      |> Keyword.put(:adapter, MeaningGame.Steward.Live)
      |> put_in([:roles, :scribe, :api_key], "recorded-responses-need-no-key")
      |> put_in([:roles, :scribe, :jobs, :title], title_job)

    Application.put_env(:meaning_game, :steward, live)
  end

  describe "fallback/1" do
    test "is deterministic from the Gives and pins three examples including 40-character cut" do
      # Example 1: two gives, trimmed and title-cased joined with " · "
      assert Title.fallback(["  summer camp  ", "viking beaches"]) ==
               "Summer Camp · Viking Beaches"

      # Example 2: single-word gives
      assert Title.fallback(["lantern", "harbour"]) == "Lantern · Harbour"

      # Example 3: long gives cut strictly at 40 characters
      # "Space Station · Mountain Solitude · Ancient Library" is 51 chars
      # The first 40 chars are "Space Station · Mountain Solitude · Anci"
      long_gives = ["space station", "mountain solitude", "ancient library"]
      result = Title.fallback(long_gives)

      assert result == "Space Station · Mountain Solitude · Anci"
      assert String.length(result) == 40
    end
  end

  describe "gate check/1" do
    test "accepts valid titles with letters, digits, spaces, hyphens and apostrophes" do
      assert Title.check(%{"title" => "Summer Drift"}) == :ok
      assert Title.check(%{"title" => "Cabin-2's Dawn"}) == :ok
      assert Title.check(%{"title" => "Cabin-2’s Dawn"}) == :ok
      assert Title.check(%{"title" => "Word"}) == :ok
    end

    test "rejects six words" do
      assert {:error, reason} = Title.check(%{"title" => "one two three four five six"})
      assert reason =~ "words"
    end

    test "rejects 41 characters" do
      title_41 = String.duplicate("a", 41)
      assert {:error, reason} = Title.check(%{"title" => title_41})
      assert reason =~ "40"
    end

    test "rejects a quoted title" do
      assert {:error, reason} = Title.check(%{"title" => "\"The Drift\""})
      assert reason =~ "quote"
      assert {:error, reason2} = Title.check(%{"title" => "‘The Drift’"})
      assert reason2 =~ "quote"
    end

    test "rejects invalid punctuation" do
      assert {:error, _reason} = Title.check(%{"title" => "Summer Drift!"})
    end
  end

  describe "prompt/1 and schema/0" do
    test "includes no song rule in system prompt, user prompt, and schema" do
      prompt = Title.prompt(["lantern", "harbour"])
      assert prompt.system =~ "No \"song\""
      assert prompt.user =~ "no \"song\""
      assert inspect(prompt.schema) =~ "no \\\"song\\\""
    end
  end

  describe "scribe title job configuration" do
    test "scribe role has a title job configured with model, effort, timeout and deadline" do
      job = Steward.role(:scribe, :title)

      assert job.model == "gemini-3.8-flash"
      assert job.effort == "low"
      assert job.timeout_ms <= 3_000
      assert job.deadline_ms <= 6_000
      assert job.provider == MeaningGame.Steward.Gemini
    end
  end

  describe "Steward.title_track/2 with Fake" do
    test "answers configured title" do
      assert {:ok, %{title: "The Porch", meta: %{}}} =
               Steward.title_track(["summer camp", "viking beaches"], title: "The Porch")
    end

    test "answers fallback when no title configured in Fake" do
      assert {:ok, %{title: "Summer Camp · Viking Beaches"}} =
               Steward.title_track(["summer camp", "viking beaches"])
    end

    test "answers error when fake title mode is unavailable" do
      steward = Application.fetch_env!(:meaning_game, :steward)
      fake = Keyword.put(steward[:fake], :title_mode, :unavailable)
      Application.put_env(:meaning_game, :steward, Keyword.put(steward, :fake, fake))
      on_exit(fn -> Application.put_env(:meaning_game, :steward, steward) end)

      assert {:error, :title_unavailable} =
               Steward.title_track(["summer camp", "viking beaches"])
    end

    test "waits for delay when configured" do
      steward = Application.fetch_env!(:meaning_game, :steward)
      fake = Keyword.put(steward[:fake], :title_delay_ms, 50)
      Application.put_env(:meaning_game, :steward, Keyword.put(steward, :fake, fake))
      on_exit(fn -> Application.put_env(:meaning_game, :steward, steward) end)

      started = System.monotonic_time(:millisecond)
      assert {:ok, %{title: _}} = Steward.title_track(["summer camp", "viking beaches"])
      elapsed = System.monotonic_time(:millisecond) - started
      assert elapsed >= 45
    end
  end

  describe "Live Scribe titling with Gate and recorded responses" do
    setup do
      live_title()
      :ok
    end

    test "a valid title from model passes gate" do
      recorded(fn conn, _body ->
        Req.Test.json(conn, title_response("Sunlit Drift"))
      end)

      assert {:ok, %{title: "Sunlit Drift", meta: %{cost_usd: cost}}} =
               Live.title_track(["summer camp", "viking beaches"])

      assert cost > 0.0
    end

    test "the gate rejects six words, retries once with reason, and accepts repaired title" do
      counts = counts()

      recorded(fn conn, body ->
        case asked(counts, :title) do
          1 ->
            # 6 words: rejected
            Req.Test.json(conn, title_response("One Two Three Four Five Six"))

          2 ->
            # Repaired answer
            user_msg = Enum.find_value(body["messages"], &(&1["role"] == "user" && &1["content"]))
            assert user_msg =~ "words"
            Req.Test.json(conn, title_response("Sunlit Drift"))
        end
      end)

      assert {:ok, %{title: "Sunlit Drift"}} =
               Live.title_track(["summer camp", "viking beaches"])

      assert Agent.get(counts, &Map.get(&1, :title)) == 2
    end

    test "the gate rejects quoted title and 41 characters, and falls back to deterministic Gives title on second failure" do
      counts = counts()

      recorded(fn conn, body ->
        case asked(counts, :title) do
          1 ->
            # Quoted title
            Req.Test.json(conn, title_response("\"Quoted Title\""))

          2 ->
            # Still invalid: 41 characters
            user_msg = Enum.find_value(body["messages"], &(&1["role"] == "user" && &1["content"]))
            assert user_msg =~ "quotes"
            Req.Test.json(conn, title_response(String.duplicate("a", 41)))
        end
      end)

      assert {:ok, %{title: "Summer Camp · Viking Beaches", meta: meta}} =
               Live.title_track(["summer camp", "viking beaches"])

      assert meta[:fallback] == true
      assert Agent.get(counts, &Map.get(&1, :title)) == 2
    end
  end
end
