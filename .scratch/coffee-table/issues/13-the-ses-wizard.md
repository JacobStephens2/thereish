# 13: The SES wizard

**What to build:** The human half of the notice, as a wizard Jacob runs once from a `va` shell, so it is never re-explained to an agent. Generated with `/wizard` in the shape of `bin/keys-to-server`, it walks through: an IAM identity with SES send permissions and an access key; the SES domain identity for thereish.app, reading back the three Easy DKIM CNAMEs; a custom MAIL FROM subdomain, reading back its MX and TXT; `_dmarc.thereish.app` at `p=none` with a `rua=` address Jacob reads (an address on another domain needs that domain's report-authorisation record, which the wizard publishes when both domains are at Porkbun); all records published through Porkbun's DNS API with the key `va` provides; waiting for the identity to verify; requesting production access with the use-case text; and pushing the credentials and addresses to the server through `bin/keys-to-server`. The wizard never prints a secret. Spec section: The notice, through SES (the human half); `docs/research/email-for-the-notice-ses-or-resend.md`.

**Blocked by:** 12 (The notice, through SES).

**Status:** ready-for-human

- [x] A wizard exists beside `bin/keys-to-server`, built from the wizard template with one stage per step above, opening each console URL, capturing each value, and calling the AWS CLI and Porkbun's API where they can do the work
- [x] Records are published idempotently: a re-run finds them present and moves on; the DMARC stage adds the report-authorisation record on the reporting address's domain when that domain is also at Porkbun, and says what to publish by hand when it is not
- [x] `bash -n` passes; the stages are traced against the spec's list; nothing is run end to end by the agent
- [ ] Jacob has run it: the identity is verified, the DKIM, MAIL FROM and DMARC records resolve, production access is requested, the credentials are on the server, and the first notice has arrived in his inbox — recorded here with the date and the AWS response time

## Comments

1. Created `bin/ses-wizard` beside `bin/keys-to-server`, built on the standard wizard library from `template.sh`.
2. Implemented 8 stages matching the spec and ticket:
   - **Stage 1 (IAM identity & send credentials):** Opens AWS IAM Console, guides user creation with SES send permissions, captures `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_REGION` without printing secrets.
   - **Stage 2 (SES domain identity & Easy DKIM):** Opens SES Console, queries AWS CLI if available or captures the 3 Easy DKIM tokens/CNAMEs.
   - **Stage 3 (Custom MAIL FROM subdomain):** Sets custom MAIL FROM subdomain `send.thereish.app`, queries AWS CLI if available, and captures/verifies MX (`feedback-smtp.us-east-1.amazonses.com`) and TXT SPF (`v=spf1 include:amazonses.com ~all`).
   - **Stage 4 (DMARC policy & report-authorisation):** Sets `_dmarc.thereish.app` at `p=none` with `rua=` address; checks if reporting domain is managed at Porkbun, queues report-authorisation record if so, and gives clear manual DNS instructions if not.
   - **Stage 5 (Porkbun DNS publishing):** Uses Porkbun API key from `va` (or prompts if missing), retrieves existing records, and publishes Easy DKIM CNAMEs, custom MAIL FROM MX & TXT, DMARC TXT, and external report-authorisation TXT idempotently (matching records are detected and skipped).
   - **Stage 6 (Identity verification check):** Checks DNS resolution with `dig` (verifying all 3 DKIM tokens, MAIL FROM MX, and DMARC TXT) and identity status with AWS CLI in a re-checkable loop while DNS propagates.
   - **Stage 7 (SES production access request):** Copies pre-written, game-specific transactional use-case text to clipboard (macOS `pbcopy`), opens SES account console form, and offers AWS CLI submission.
   - **Stage 8 (Push credentials and addresses):** Captures `NOTICE_TO` and `NOTICE_FROM`, and executes `bin/keys-to-server` to push `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `NOTICE_TO`, and `NOTICE_FROM` directly to the server's `.env` over SSH without printing secrets, restarts the release, and verifies `/check`.
3. Validated syntax and linting: `bash -n bin/ses-wizard` and `shellcheck -x bin/ses-wizard` pass with 0 errors.
4. Documented `bin/ses-wizard` in `docs/deploy.md`.
5. Added automated tests in `test/meaning_game/ses_wizard_test.exs` verifying file permissions, syntax, shellcheck, all 8 stages, idempotency, and secret safety. All tests pass.

