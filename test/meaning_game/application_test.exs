defmodule MeaningGame.ApplicationTest do
  @moduledoc """
  Tests for boot-time checks and warnings (ticket 11: Umami counts the door).
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  setup do
    original_config = Application.get_env(:meaning_game, :umami)

    on_exit(fn ->
      if original_config do
        Application.put_env(:meaning_game, :umami, original_config)
      else
        Application.delete_env(:meaning_game, :umami)
      end
    end)

    :ok
  end

  describe "Umami boot warning" do
    test "warns when both UMAMI_SCRIPT_URL and UMAMI_WEBSITE_ID are missing" do
      Application.put_env(:meaning_game, :umami, script_url: nil, website_id: nil)

      log =
        capture_log(fn ->
          MeaningGame.Application.warn_missing_keys()
        end)

      assert log =~ "UMAMI_SCRIPT_URL and UMAMI_WEBSITE_ID are not set"
      assert log =~ "page views will not be counted"
    end

    test "warns when UMAMI_SCRIPT_URL is missing" do
      Application.put_env(:meaning_game, :umami,
        script_url: nil,
        website_id: "test-website-id"
      )

      log =
        capture_log(fn ->
          MeaningGame.Application.warn_missing_keys()
        end)

      assert log =~ "UMAMI_SCRIPT_URL is not set"
      assert log =~ "page views will not be counted"
    end

    test "warns when UMAMI_WEBSITE_ID is missing" do
      Application.put_env(:meaning_game, :umami,
        script_url: "https://umami.example.com/script.js",
        website_id: nil
      )

      log =
        capture_log(fn ->
          MeaningGame.Application.warn_missing_keys()
        end)

      assert log =~ "UMAMI_WEBSITE_ID is not set"
      assert log =~ "page views will not be counted"
    end

    test "is silent when both UMAMI_SCRIPT_URL and UMAMI_WEBSITE_ID are configured" do
      Application.put_env(:meaning_game, :umami,
        script_url: "https://umami.example.com/script.js",
        website_id: "test-website-id"
      )

      log =
        capture_log(fn ->
          MeaningGame.Application.warn_missing_keys()
        end)

      refute log =~ "UMAMI"
    end
  end
end
