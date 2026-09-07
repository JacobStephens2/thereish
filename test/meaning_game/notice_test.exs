defmodule MeaningGame.NoticeTest do
  use ExUnit.Case, async: true
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
    # Plain-text notice, no HTML body
    assert email.html_body == nil
  end

  test "warn_at_boot/1 logs a warning naming missing names when absent" do
    log =
      capture_log(fn ->
        Notice.warn_at_boot(%{})
      end)

    assert log =~ "AWS_ACCESS_KEY_ID"
    assert log =~ "AWS_SECRET_ACCESS_KEY"
    assert log =~ "AWS_REGION"
    assert log =~ "NOTICE_TO"
    assert log =~ "NOTICE_FROM"
  end

  test "warn_at_boot/1 is silent when all credentials are present" do
    env = %{
      "AWS_ACCESS_KEY_ID" => "key",
      "AWS_SECRET_ACCESS_KEY" => "secret",
      "AWS_REGION" => "us-east-1",
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
