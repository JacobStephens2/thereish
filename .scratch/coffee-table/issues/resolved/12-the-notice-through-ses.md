# 12: The notice, through SES

**What to build:** When a Room is opened from a device that has never played, Jacob gets an email that day. Swoosh joins the dependencies with a Mailer module — this app was generated without one, and ADR-0007's magic links will want it — configured with the Amazon SES adapter in production (which needs `gen_smtp` for the raw message and speaks SES's v1 Query API), the Local adapter in development with the mailbox preview, and the Test adapter in tests. Credentials and addresses are runtime configuration: the AWS access key, secret and region, the operator's address and a sender at thereish.app. When a Room is created for a device token that holds no Seat anywhere — the check the Scribe's naming already makes — a supervised task delivers one plain-text notice: the Code, the player count, the time, a link. A returning device sends nothing. Delivery never blocks or fails creation; a failure is logged; with no credentials configured the Mailer is never called and one boot line names the missing names. Provable end to end with the Test adapter before any AWS account exists; the account, the identity and the DNS are 13. Spec section: The notice, through SES.

**Blocked by:** None (can start immediately).

**Status:** resolved

- [x] Swoosh and `gen_smtp` are dependencies; a Mailer module exists; the SES adapter is configured in production from `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, the Local adapter with the `/dev/mailbox` preview in development, the Test adapter in tests
- [x] `NOTICE_TO` and `NOTICE_FROM` are runtime configuration; creating a Room from a device with no history delivers exactly one notice carrying the Code, the count, the time and a link; a device with history delivers none
- [x] Delivery runs in a supervised task; a Mailer that raises or times out leaves creation successful and logs; with no credentials the Mailer is not called and one boot line names the missing names
- [x] `bin/deploy` warns on the missing AWS and notice names; `bin/keys-to-server` lists them with what they buy
- [x] Room tests through the Test adapter for the two paths and the failure; a boot-line test for present and absent credentials

## Answer

1. Added `{:swoosh, "~> 1.16"}` and `{:gen_smtp, "~> 1.2"}` to `mix.exs`.
2. Created `MeaningGame.Mailer` using `Swoosh.Mailer, otp_app: :meaning_game`.
3. Configured adapters:
   - `Swoosh.Adapters.Test` in `config/test.exs`
   - `Swoosh.Adapters.Local` in `config/dev.exs` with `/dev/mailbox` mounted in `MeaningGameWeb.Router` under `dev_routes`
   - `Swoosh.Adapters.AmazonSES` in `config/runtime.exs` for `:prod` using `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_REGION` (defaulting to "us-east-1").
   - Swoosh API client configured with `Swoosh.ApiClient.Req`.
4. Runtime configuration for `NOTICE_TO` and `NOTICE_FROM` added in `config/runtime.exs`.
5. Created `MeaningGame.Notice` to format plain-text emails containing the Room Code, player count, ISO8601 time, and verified route link (`/r/:code`), delivering via `MeaningGame.Notice.Tasks` supervised task.
6. Updated `Rooms.create/2` to trigger the notice task when creating a Room for a device token that holds no Seat anywhere (`Store.rooms_for_device(device_token) == []`). Returning devices send nothing. Delivery runs asynchronously and never blocks or fails room creation.
7. Handled missing credentials: with no credentials configured, `MeaningGame.Mailer` is never called; `MeaningGame.Notice.warn_at_boot/1` logs a single warning at boot naming all missing names when credentials are absent, and stays silent when present.
8. Updated `bin/deploy` to check and warn on missing AWS (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`) and notice names (`NOTICE_TO`, `NOTICE_FROM`).
9. Updated `bin/keys-to-server` with all 5 keys and their descriptions in `buys()`.
10. Added full test coverage in `test/meaning_game/notice_test.exs`, `test/meaning_game/mailer_test.exs`, and `test/meaning_game/rooms_test.exs`. All 616 tests pass.
