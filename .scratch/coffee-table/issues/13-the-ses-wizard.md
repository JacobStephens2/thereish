# 13: The SES wizard

**What to build:** The human half of the notice, as a wizard Jacob runs once from a `va` shell, so it is never re-explained to an agent. Generated with `/wizard` in the shape of `bin/keys-to-server`, it walks through: an IAM identity with SES send permissions and an access key; the SES domain identity for thereish.app, reading back the three Easy DKIM CNAMEs; a custom MAIL FROM subdomain, reading back its MX and TXT; `_dmarc.thereish.app` at `p=none` with a `rua=` address Jacob reads (an address on another domain needs that domain's report-authorisation record, which the wizard publishes when both domains are at Porkbun); all records published through Porkbun's DNS API with the key `va` provides; waiting for the identity to verify; requesting production access with the use-case text; and pushing the credentials and addresses to the server through `bin/keys-to-server`. The wizard never prints a secret. Spec section: The notice, through SES (the human half); `docs/research/email-for-the-notice-ses-or-resend.md`.

**Blocked by:** 12 (The notice, through SES).

**Status:** ready-for-agent

- [ ] A wizard exists beside `bin/keys-to-server`, built from the wizard template with one stage per step above, opening each console URL, capturing each value, and calling the AWS CLI and Porkbun's API where they can do the work
- [ ] Records are published idempotently: a re-run finds them present and moves on; the DMARC stage adds the report-authorisation record on the reporting address's domain when that domain is also at Porkbun, and says what to publish by hand when it is not
- [ ] `bash -n` passes; the stages are traced against the spec's list; nothing is run end to end by the agent
- [ ] Jacob has run it: the identity is verified, the DKIM, MAIL FROM and DMARC records resolve, production access is requested, the credentials are on the server, and the first notice has arrived in his inbox — recorded here with the date and the AWS response time
