defmodule MeaningGame.MailerTest do
  use ExUnit.Case, async: true
  import Swoosh.TestAssertions
  import Swoosh.Email

  test "Mailer delivers through Swoosh.Adapters.Test in test environment" do
    email =
      new()
      |> to("operator@example.com")
      |> from("notice@thereish.app")
      |> subject("Test Subject")
      |> text_body("Test Body")

    assert {:ok, _metadata} = MeaningGame.Mailer.deliver(email)
    assert_email_sent(email)
  end
end
