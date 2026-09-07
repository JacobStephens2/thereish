defmodule MeaningGame.SesWizardTest do
  use ExUnit.Case, async: true

  @wizard_script Path.expand("../../bin/ses-wizard", __DIR__)

  test "bin/ses-wizard exists and is executable" do
    assert File.exists?(@wizard_script), "Expected #{@wizard_script} to exist"
    stat = File.stat!(@wizard_script)
    assert Bitwise.band(stat.mode, 0o111) != 0, "Expected #{@wizard_script} to be executable"
  end

  test "bash -n passes on bin/ses-wizard" do
    {output, exit_code} = System.cmd("bash", ["-n", @wizard_script], stderr_to_stdout: true)
    assert exit_code == 0, "bash -n failed with output:\n#{output}"
  end

  test "shellcheck passes on bin/ses-wizard" do
    if System.find_executable("shellcheck") do
      {output, exit_code} =
        System.cmd("shellcheck", ["-x", @wizard_script], stderr_to_stdout: true)

      assert exit_code == 0, "shellcheck failed with output:\n#{output}"
    end
  end

  test "bin/ses-wizard defines 8 stages matching ticket 13 and coffee-table spec" do
    content = File.read!(@wizard_script)

    assert content =~ ~r/TOTAL_STAGES=8/

    # Stage 1: IAM identity with SES send permissions & access key
    assert content =~ ~r/IAM identity/i
    assert content =~ "AWS_ACCESS_KEY_ID"
    assert content =~ "AWS_SECRET_ACCESS_KEY"
    assert content =~ "AWS_REGION"

    # Stage 2: SES domain identity for thereish.app, reading back Easy DKIM CNAMEs
    assert content =~ ~r/domain identity/i
    assert content =~ ~r/DKIM/i
    assert content =~ "_domainkey"

    # Stage 3: Custom MAIL FROM subdomain, reading back MX and TXT
    assert content =~ ~r/MAIL FROM/i
    assert content =~ "feedback-smtp"
    assert content =~ "v=spf1 include:amazonses.com"
    assert content =~ "ask MAIL_FROM_MX"
    assert content =~ "ask MAIL_FROM_TXT"

    # Stage 4: DMARC at p=none with rua= and cross-domain report-authorisation
    assert content =~ ~r/_dmarc/i
    assert content =~ "p=none"
    assert content =~ "rua="
    assert content =~ "_report._dmarc"

    # Stage 5: DNS publishing through Porkbun API idempotently
    assert content =~ "api.porkbun.com"
    assert content =~ "PORKBUN_API_KEY"
    assert content =~ ~r/already exists|already present/i

    # Stage 6: Waiting for identity verification (verifying all DKIM tokens)
    assert content =~ ~r/verif/i

    # Stage 7: Requesting production access with use-case text
    assert content =~ ~r/production access/i
    assert content =~ ~r/transactional/i
    assert content =~ ~r/magic-link|word game/i

    # Stage 8: Pushing credentials and addresses through bin/keys-to-server
    assert content =~ "keys-to-server"
    assert content =~ "NOTICE_TO"
    assert content =~ "NOTICE_FROM"
  end

  test "bin/ses-wizard never prints secrets" do
    content = File.read!(@wizard_script)

    # Uses ask_secret for secret values
    assert content =~ ~r/ask_secret.*AWS_SECRET_ACCESS_KEY/
    assert content =~ ~r/ask_secret.*PORKBUN_SECRET/

    # Ensure no echo/printf statements expose the secret values
    refute content =~ ~r/echo.*\$AWS_SECRET_ACCESS_KEY/
    refute content =~ ~r/printf.*\$AWS_SECRET_ACCESS_KEY/
    refute content =~ ~r/echo.*\$PORKBUN_SECRET/
    refute content =~ ~r/printf.*\$PORKBUN_SECRET/
  end

  test "bin/ses-wizard handles DMARC report-authorisation for Porkbun and non-Porkbun domains" do
    content = File.read!(@wizard_script)

    # Checks if reporting domain is at Porkbun
    assert content =~ ~r/porkbun/i
    # Gives manual publishing instructions if not at Porkbun
    assert content =~ ~r/by hand|manual/i
  end
end
