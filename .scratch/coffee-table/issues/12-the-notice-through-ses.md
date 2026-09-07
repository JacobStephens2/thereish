# 12: The notice, through SES

**What to build:** When a Room is opened from a device that has never played, Jacob gets an email that day. Swoosh joins the dependencies with a Mailer module — this app was generated without one, and ADR-0007's magic links will want it — configured with the Amazon SES adapter in production (which needs `gen_smtp` for the raw message and speaks SES's v1 Query API), the Local adapter in development with the mailbox preview, and the Test adapter in tests. Credentials and addresses are runtime configuration: the AWS access key, secret and region, the operator's address and a sender at thereish.app. When a Room is created for a device token that holds no Seat anywhere — the check the Scribe's naming already makes — a supervised task delivers one plain-text notice: the Code, the player count, the time, a link. A returning device sends nothing. Delivery never blocks or fails creation; a failure is logged; with no credentials configured the Mailer is never called and a boot line says so. Provable end to end with the Test adapter before any AWS account exists; the account, the identity and the DNS are 13. Spec section: The notice, through SES.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] Swoosh and `gen_smtp` are dependencies; a Mailer module exists; the SES adapter is configured in production from `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_REGION`, the Local adapter with the `/dev/mailbox` preview in development, the Test adapter in tests
- [ ] `NOTICE_TO` and `NOTICE_FROM` are runtime configuration; creating a Room from a device with no history delivers exactly one notice carrying the Code, the count, the time and a link; a device with history delivers none
- [ ] Delivery runs in a supervised task; a Mailer that raises or times out leaves creation successful and logs; with no credentials the Mailer is not called and one boot line names the missing names
- [ ] `bin/deploy` warns on the missing AWS and notice names; `bin/keys-to-server` lists them with what they buy
- [ ] Room tests through the Test adapter for the two paths and the failure; a boot-line test for present and absent credentials
