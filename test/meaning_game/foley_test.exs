defmodule MeaningGame.FoleyTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias MeaningGame.Foley

  setup do
    original_steward = Application.get_env(:meaning_game, :steward)

    on_exit(fn ->
      Application.put_env(:meaning_game, :steward, original_steward)
    end)

    :ok
  end

  describe "warn_missing_keys/0" do
    test "silent when all keys are present" do
      # In the test environment, all keys are populated with test placeholders
      log =
        capture_log(fn ->
          assert :ok = Foley.warn_missing_keys()
        end)

      assert log == ""
    end

    test "warns when MUREKA_API_KEY is missing" do
      steward = Application.get_env(:meaning_game, :steward)
      roles = steward[:roles]
      foley = roles[:foley]
      jobs = foley[:jobs]
      music = Keyword.put(jobs[:music], :api_key, nil)
      jobs = Keyword.put(jobs, :music, music)
      foley = Keyword.put(foley, :jobs, jobs)
      roles = Keyword.put(roles, :foley, foley)
      Application.put_env(:meaning_game, :steward, Keyword.put(steward, :roles, roles))

      log =
        capture_log(fn ->
          assert :ok = Foley.warn_missing_keys()
        end)

      assert log =~ "no MUREKA_API_KEY — every Page will have only the house loop"
      refute log =~ "voice switch"
    end

    test "warns when Hume keys are missing" do
      steward = Application.get_env(:meaning_game, :steward)
      roles = steward[:roles]

      foley =
        roles[:foley]
        |> Keyword.put(:hume_api_key, nil)
        |> Keyword.put(:hume_secret_key, nil)

      roles = Keyword.put(roles, :foley, foley)
      Application.put_env(:meaning_game, :steward, Keyword.put(steward, :roles, roles))

      log =
        capture_log(fn ->
          assert :ok = Foley.warn_missing_keys()
        end)

      assert log =~ "the voice switch will do nothing"
      assert log =~ "HUME_API_KEY"
      assert log =~ "HUME_SECRET_KEY"
      refute log =~ "MUREKA_API_KEY"
    end

    test "voice warning follows configured voice provider (ElevenLabs)" do
      steward = Application.get_env(:meaning_game, :steward)
      roles = steward[:roles]
      foley = roles[:foley]
      jobs = foley[:jobs]

      voice =
        jobs[:voice]
        |> Keyword.put(:provider, MeaningGame.Steward.ElevenLabs)

      jobs = Keyword.put(jobs, :voice, voice)

      foley =
        foley
        |> Keyword.put(:jobs, jobs)
        |> Keyword.put(:elevenlabs_api_key, nil)
        # Even if Hume keys were nil, they should not be warned about
        |> Keyword.put(:hume_api_key, nil)
        |> Keyword.put(:hume_secret_key, nil)

      roles = Keyword.put(roles, :foley, foley)
      Application.put_env(:meaning_game, :steward, Keyword.put(steward, :roles, roles))

      log =
        capture_log(fn ->
          assert :ok = Foley.warn_missing_keys()
        end)

      assert log =~ "no ELEVENLABS_API_KEY — the voice switch will do nothing"
      refute log =~ "HUME"
    end

    test "warns once per Foley job when both music and voice have no keys" do
      steward = Application.get_env(:meaning_game, :steward)
      roles = steward[:roles]
      foley = roles[:foley]
      jobs = foley[:jobs]
      music = Keyword.put(jobs[:music], :api_key, nil)
      jobs = Keyword.put(jobs, :music, music)

      foley =
        foley
        |> Keyword.put(:jobs, jobs)
        |> Keyword.put(:hume_api_key, nil)
        |> Keyword.put(:hume_secret_key, nil)

      roles = Keyword.put(roles, :foley, foley)
      Application.put_env(:meaning_game, :steward, Keyword.put(steward, :roles, roles))

      log =
        capture_log(fn ->
          assert :ok = Foley.warn_missing_keys()
        end)

      # One warning for music
      assert log =~ "no MUREKA_API_KEY — every Page will have only the house loop"
      # One warning for voice
      assert log =~ "the voice switch will do nothing"
      assert log =~ "HUME_API_KEY"
      assert log =~ "HUME_SECRET_KEY"
    end
  end
end
