defmodule Thereish.ApplicationTest do
  @moduledoc """
  Tests for boot-time checks and warnings (ticket 11: Umami counts the door).
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  setup do
    original_config = Application.get_env(:thereish, :umami)
    original_boot_warnings = Application.get_env(:thereish, :boot_warnings)

    on_exit(fn ->
      if original_config do
        Application.put_env(:thereish, :umami, original_config)
      else
        Application.delete_env(:thereish, :umami)
      end

      if original_boot_warnings != nil do
        Application.put_env(:thereish, :boot_warnings, original_boot_warnings)
      else
        Application.delete_env(:thereish, :boot_warnings)
      end
    end)

    :ok
  end

  describe "Umami boot warning" do
    test "warns when both UMAMI_SCRIPT_URL and UMAMI_WEBSITE_ID are missing" do
      Application.put_env(:thereish, :umami, script_url: nil, website_id: nil)

      log =
        capture_log(fn ->
          Thereish.Umami.warn_missing_keys()
        end)

      assert log =~ "no UMAMI_SCRIPT_URL and UMAMI_WEBSITE_ID — Umami will count nothing"
    end

    test "warns when UMAMI_SCRIPT_URL is missing" do
      Application.put_env(:thereish, :umami,
        script_url: nil,
        website_id: "test-website-id"
      )

      log =
        capture_log(fn ->
          Thereish.Umami.warn_missing_keys()
        end)

      assert log =~ "no UMAMI_SCRIPT_URL — Umami will count nothing"
    end

    test "warns when UMAMI_WEBSITE_ID is missing" do
      Application.put_env(:thereish, :umami,
        script_url: "https://umami.example.com/script.js",
        website_id: nil
      )

      log =
        capture_log(fn ->
          Thereish.Umami.warn_missing_keys()
        end)

      assert log =~ "no UMAMI_WEBSITE_ID — Umami will count nothing"
    end

    test "is silent when both UMAMI_SCRIPT_URL and UMAMI_WEBSITE_ID are configured" do
      Application.put_env(:thereish, :umami,
        script_url: "https://umami.example.com/script.js",
        website_id: "test-website-id"
      )

      log =
        capture_log(fn ->
          Thereish.Umami.warn_missing_keys()
        end)

      assert log == ""
    end

    test "delegates warn_missing_keys on Thereish.Application" do
      Application.put_env(:thereish, :umami, script_url: nil, website_id: nil)

      log =
        capture_log(fn ->
          Thereish.Application.warn_missing_keys()
        end)

      assert log =~ "no UMAMI_SCRIPT_URL and UMAMI_WEBSITE_ID — Umami will count nothing"
    end

    test "warn_at_boot is silent when boot_warnings is disabled" do
      Application.put_env(:thereish, :boot_warnings, false)
      Application.put_env(:thereish, :umami, script_url: nil, website_id: nil)

      log =
        capture_log(fn ->
          Thereish.Umami.warn_at_boot()
        end)

      assert log == ""
    end

    test "application boot invokes Umami key warning when boot_warnings is enabled" do
      Application.put_env(:thereish, :boot_warnings, true)
      Application.put_env(:thereish, :umami, script_url: nil, website_id: nil)

      log =
        capture_log(fn ->
          _ = Thereish.Application.start(:normal, [])
        end)

      assert log =~ "no UMAMI_SCRIPT_URL and UMAMI_WEBSITE_ID — Umami will count nothing"
    end
  end
end
