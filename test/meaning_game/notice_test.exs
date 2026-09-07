defmodule MeaningGame.NoticeTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias MeaningGame.Notice

  test "build_email/3 builds a plain-text notice carrying Code, count, time, and link" do
    time = ~U[2026-09-07 00:00:00Z]
    email = Notice.build_email("CANE", 2, time)

    assert email.to == [{"", "operator@example.com"}]
    assert email.from == {"", "notice@thereish.app"}
    assert email.subject =~ "CANE"
    assert email.text_body =~ "CANE"
    assert email.text_body =~ "2"
    assert email.text_body =~ "2026-09-07"
    assert email.text_body =~ "/r/CANE"
    assert email.html_body == nil
  end

  test "configured?/0 returns true when mailer and addresses are configured" do
    assert Notice.configured?()

    previous_notice = Application.get_env(:meaning_game, :notice)
    Application.put_env(:meaning_game, :notice, to: nil, from: nil)
    refute Notice.configured?()

    Application.put_env(:meaning_game, :notice, previous_notice)
  end

  test "configured?/0 checks AmazonSES credentials when using AmazonSES adapter" do
    previous_mailer = Application.get_env(:meaning_game, MeaningGame.Mailer)

    Application.put_env(:meaning_game, MeaningGame.Mailer,
      adapter: Swoosh.Adapters.AmazonSES,
      access_key: nil,
      secret: nil
    )

    refute Notice.configured?()

    Application.put_env(:meaning_game, MeaningGame.Mailer,
      adapter: Swoosh.Adapters.AmazonSES,
      access_key: "key",
      secret: "secret"
    )

    assert Notice.configured?()

    Application.put_env(:meaning_game, MeaningGame.Mailer, previous_mailer)
  end

  test "warn_at_boot/1 logs a warning naming missing names when absent" do
    log =
      capture_log(fn ->
        Notice.warn_at_boot(%{})
      end)

    assert log =~ "AWS_ACCESS_KEY_ID"
    assert log =~ "AWS_SECRET_ACCESS_KEY"
    assert log =~ "NOTICE_TO"
    assert log =~ "NOTICE_FROM"
  end

  test "warn_at_boot/1 is silent when all credentials are present" do
    env = %{
      "AWS_ACCESS_KEY_ID" => "key",
      "AWS_SECRET_ACCESS_KEY" => "secret",
      "NOTICE_TO" => "operator@example.com",
      "NOTICE_FROM" => "notice@thereish.app"
    }

    log =
      capture_log(fn ->
        Notice.warn_at_boot(env)
      end)

    assert log == ""
  end
end
