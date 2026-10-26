defmodule Thereish.Steward.WarnMissingFoleyKeysTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  setup do
    original_steward = Application.get_env(:thereish, :steward)

    on_exit(fn ->
      Application.put_env(:thereish, :steward, original_steward)
    end)

    :ok
  end

  describe "warn_missing_foley_keys/0" do
    test "silent when all keys are present" do
      # In the test environment, all keys are populated with test placeholders
      log =
        capture_log(fn ->
          assert :ok = Thereish.Steward.warn_missing_foley_keys()
        end)

      assert log == ""
    end

    test "warns when the music provider's key is missing" do
      configure_foley([lyria_api_key: nil], music: [api_key: nil])

      log =
        capture_log(fn ->
          assert :ok = Thereish.Steward.warn_missing_foley_keys()
        end)

      assert log =~ "no GEMINI_API_KEY — every Page will have only the house loop"
      refute log =~ "voice switch"
    end

    test "warns when Hume keys are missing" do
      configure_foley(hume_api_key: nil, hume_secret_key: nil)

      log =
        capture_log(fn ->
          assert :ok = Thereish.Steward.warn_missing_foley_keys()
        end)

      assert log =~ "the voice switch will do nothing"
      assert log =~ "HUME_API_KEY"
      assert log =~ "HUME_SECRET_KEY"
      refute log =~ "GEMINI_API_KEY"
    end

    test "voice warning follows configured voice provider (ElevenLabs)" do
      configure_foley(
        [eleven_labs_api_key: nil, hume_api_key: nil, hume_secret_key: nil],
        voice: [provider: Thereish.Steward.ElevenLabs]
      )

      log =
        capture_log(fn ->
          assert :ok = Thereish.Steward.warn_missing_foley_keys()
        end)

      assert log =~ "no ELEVENLABS_API_KEY — the voice switch will do nothing"
      refute log =~ "HUME"
    end

    test "warns once per Foley job when both music and voice have no keys" do
      configure_foley(
        [lyria_api_key: nil, hume_api_key: nil, hume_secret_key: nil],
        music: [api_key: nil]
      )

      log =
        capture_log(fn ->
          assert :ok = Thereish.Steward.warn_missing_foley_keys()
        end)

      # One warning for music
      assert log =~ "no GEMINI_API_KEY — every Page will have only the house loop"
      # One warning for voice
      assert log =~ "the voice switch will do nothing"
      assert log =~ "HUME_API_KEY"
      assert log =~ "HUME_SECRET_KEY"
    end

    test "application boot invokes Foley key warning" do
      configure_foley([lyria_api_key: nil], music: [api_key: nil])

      log =
        capture_log(fn ->
          _ = Thereish.Application.start(:normal, [])
        end)

      assert log =~ "no GEMINI_API_KEY — every Page will have only the house loop"
    end

    test "application boot invokes Limner key warning" do
      configure_limner(
        provider: Thereish.Steward.Recraft,
        recraft_api_key: nil,
        api_key: nil
      )

      log =
        capture_log(fn ->
          _ = Thereish.Application.start(:normal, [])
        end)

      assert log =~ "no RECRAFT_AI_API_KEY — every Seat will wear a colour dot"
    end

    test "warns when the Limner's Recraft key is missing" do
      configure_limner(
        provider: Thereish.Steward.Recraft,
        recraft_api_key: nil,
        api_key: nil
      )

      log =
        capture_log(fn ->
          assert :ok = Thereish.Steward.warn_missing_limner_keys()
        end)

      assert log =~ "no RECRAFT_AI_API_KEY — every Seat will wear a colour dot"
    end

    test "Limner warning is silent when Recraft key is present" do
      configure_limner(
        provider: Thereish.Steward.Recraft,
        recraft_api_key: "recorded-responses-need-no-key"
      )

      log =
        capture_log(fn ->
          assert :ok = Thereish.Steward.warn_missing_limner_keys()
        end)

      refute log =~ "RECRAFT_AI_API_KEY"
      refute log =~ "colour dot"
    end

    test "Limner warning follows the configured provider" do
      for {provider, env} <- [
            {Thereish.Steward.Fal, "FAL_AI_API_KEY"},
            {Thereish.Steward.Ideogram, "IDEOGRAM_API_KEY"},
            {Thereish.Steward.Bfl, "BFL_API_KEY"}
          ] do
        configure_limner(provider: provider, api_key: nil)

        log =
          capture_log(fn ->
            assert :ok = Thereish.Steward.warn_missing_limner_keys()
          end)

        assert log =~ "no #{env} — every Seat will wear a colour dot"
        refute log =~ "RECRAFT_AI_API_KEY"
      end
    end

    test "Limner warning is silent when the vendor-scoped key is present" do
      configure_limner(
        provider: Thereish.Steward.Fal,
        api_key: nil,
        fal_api_key: "recorded-responses-need-no-key"
      )

      log =
        capture_log(fn ->
          assert :ok = Thereish.Steward.warn_missing_limner_keys()
        end)

      assert log == ""
    end

    test "Limner warning treats an empty key as missing" do
      configure_limner(provider: Thereish.Steward.Recraft, api_key: "", recraft_api_key: "")

      log =
        capture_log(fn ->
          assert :ok = Thereish.Steward.warn_missing_limner_keys()
        end)

      assert log =~ "no RECRAFT_AI_API_KEY — every Seat will wear a colour dot"
    end

    test "application boot is silent when all keys are present" do
      log =
        capture_log(fn ->
          _ = Thereish.Application.start(:normal, [])
        end)

      assert log == ""
    end
  end

  defp configure_foley(foley_updates, job_updates \\ []) do
    steward = Application.get_env(:thereish, :steward)
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
    Application.put_env(:thereish, :steward, Keyword.put(steward, :roles, roles))
  end

  defp configure_limner(updates) do
    steward = Application.get_env(:thereish, :steward)
    roles = steward[:roles]
    limner = Keyword.merge(roles[:limner], updates)
    roles = Keyword.put(roles, :limner, limner)
    Application.put_env(:thereish, :steward, Keyword.put(steward, :roles, roles))
  end
end
