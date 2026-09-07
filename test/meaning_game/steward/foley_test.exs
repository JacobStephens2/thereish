defmodule MeaningGame.Steward.FoleyTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias MeaningGame.Steward.Foley

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
      configure_foley([], music: [api_key: nil])

      log =
        capture_log(fn ->
          assert :ok = Foley.warn_missing_keys()
        end)

      assert log =~ "no MUREKA_API_KEY — every Page will have only the house loop"
      refute log =~ "voice switch"
    end

    test "warns when Hume keys are missing" do
      configure_foley(hume_api_key: nil, hume_secret_key: nil)

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
      configure_foley(
        [elevenlabs_api_key: nil, hume_api_key: nil, hume_secret_key: nil],
        voice: [provider: MeaningGame.Steward.ElevenLabs]
      )

      log =
        capture_log(fn ->
          assert :ok = Foley.warn_missing_keys()
        end)

      assert log =~ "no ELEVENLABS_API_KEY — the voice switch will do nothing"
      refute log =~ "HUME"
    end

    test "warns once per Foley job when both music and voice have no keys" do
      configure_foley(
        [hume_api_key: nil, hume_secret_key: nil],
        music: [api_key: nil]
      )

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

  defp configure_foley(foley_updates, job_updates \\ []) do
    steward = Application.get_env(:meaning_game, :steward)
    roles = steward[:roles]
    foley = roles[:foley]

    jobs =
      Enum.reduce(job_updates, foley[:jobs], fn {job, updates}, acc ->
        Keyword.update(acc, job, updates, &Keyword.merge(&1, updates))
      end)

    foley =
      foley
      |> Keyword.merge(foley_updates)
      |> Keyword.put(:jobs, jobs)

    roles = Keyword.put(roles, :foley, foley)
    Application.put_env(:meaning_game, :steward, Keyword.put(steward, :roles, roles))
  end
end
