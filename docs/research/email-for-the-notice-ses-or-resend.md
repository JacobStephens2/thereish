# Email for the Room-created notice — is Amazon SES worth learning, or is Resend already the same thing?

Researched 2026-09-06 for the [design brief](../design-brief.md). Question: Thereish wants to send one small transactional message — a notice to the operator when a Room is created from a device with no play history, a few a week at most — and, under [ADR-0007](../adr/0007-n-seat-rooms-joined-by-name-claimable-later.md), the same transport must later carry magic-link login mails to players who claim a seat. The app has **no mailer dependency today**: `mix.exs` lists `{:phoenix, "~> 1.8.13"}` and `{:req, "~> 0.5"}` but no `:swoosh`, no `:bamboo`, no `:gen_smtp`. The operator already runs Resend for `stephens.page`, wants to learn a production-grade email system — Amazon SES specifically, "partly for the fun of learning" — and asked whether Resend is built on SES anyway. What does the evidence actually say, and what does each route cost in setup, money and 2 a.m. failure modes?

Method: every claim traces to a primary source — AWS documentation and the SES pricing page, Resend's own docs, legal pages and status page, vendor pricing pages, hexdocs and hex.pm package pages, the Gmail and Yahoo sender-guideline pages, and the RFC Editor — all fetched 2026-09-06. Where a page does not state a fact the text says **not found** and nothing is invented. Section 1 additionally reports **live public DNS**, read with `dig` on 2026-09-06 and quoted verbatim; DNS is evidence about configuration, not a vendor statement, and §1c separates the two. The only arithmetic is the cost table in §7, which shows its working. §8 states implications; the single recommendation is labelled as such and is the last paragraph.

---

## 1. Is Resend built on Amazon SES?

### 1a. What Resend documents

**The subprocessor list names AWS as a *sending* provider.** Resend's legal page lists 22 subprocessors; the first entry is:

> **Amazon Web Services, Inc. (USA)**: "Third party hosting and sending provider"

([subprocessors](https://resend.com/legal/subprocessors)). The word "sending" — not merely "hosting" — is Resend's own. This is the cleanest documented statement available. It names AWS, not SES by name.

**Resend's own troubleshooting doc prints an SES hostname.** The domain-verification troubleshooting page walks through DNS providers that append the apex to a record and produce `feedback-smtp.eu-west-1.amazonses.com.example.com` instead of the correct `feedback-smtp.eu-west-1.amazonses.com`, and says of the region: "The region your domain is added to is in this MX record. It may be `us-east-1`, `eu-west-1`, `ap-northeast-1`, or `sa-east-1` depending on the region" ([what if my domain is not verifying](https://resend.com/docs/knowledge-base/what-if-my-domain-is-not-verifying)). `feedback-smtp.<region>.amazonses.com` is the exact hostname AWS documents as the SES **feedback endpoint** for a custom MAIL FROM domain ([AWS SES endpoints and quotas](https://docs.aws.amazon.com/general/latest/gr/ses.html)).

**Resend's regions are AWS region codes.** "North Virginia (us-east-1), Ireland (eu-west-1), São Paulo (sa-east-1), Tokyo (ap-northeast-1)"; "Region selection controls where your emails are routed and sent from. It does not control where customer data is stored," and "All account data, including email metadata, logs, and API records, is stored in the United States" ([regions](https://resend.com/docs/dashboard/domains/regions)). The page does not say "AWS"; the codes are AWS's.

**Resend is moving the SES surface out of sight.** The domain-management doc says "SPF-related records are not always shown as TXT and MX records. For domains created after August 2026, Resend may generate CNAME records instead," and instructs you to "make sure to always add the exact records shown in your domain's **Records** tab within the Resend dashboard" rather than any values printed in the docs ([manage domains](https://resend.com/docs/dashboard/domains/manage-domains)). So a domain verified today may never show an `amazonses.com` string at all.

**What is not there.** Resend's engineering handbook names its AWS usage as "Lambda, ECS Fargate, CloudWatch" but does **not** name SES or any email-sending infrastructure ([tech stack](https://resend.com/handbook/engineering/what-is-our-tech-stack)). Resend's status page lists only its own components — Email Sending, SMTP, General API, Email Events, Automations, Webhooks, Dashboard, Website — and **no upstream or third-party dependency** ([status](https://resend-status.com/), reached from `status.resend.com`). No Resend blog post naming SES as its sending infrastructure was found. A `resend.com/docs/dashboard/domains/cluster-region` page does not exist (404).

**Resend's own corporate mail is sent through SES.** Read today:

```
$ dig +short TXT send.resend.com
"v=spf1 include:amazonses.com ~all"

$ dig +short MX send.resend.com
10 feedback-smtp.us-east-1.amazonses.com.
```

That is the SES custom-MAIL-FROM shape exactly as AWS specifies it ([custom MAIL FROM](https://docs.aws.amazon.com/ses/latest/dg/mail-from.html)), on Resend's own domain. Resend's apex publishes `"v=spf1 include:_spf.google.com ~all"` and `_dmarc.resend.com` publishes `"v=DMARC1; p=reject; pct=100; rua=mailto:ozsm6m1q@ag.us.dmarcian.com,mailto:dmarcreports@resend.com; ruf=mailto:ozsm6m1q@fr.us.dmarcian.com; fo=1;"`.

### 1b. What `stephens.page` looks like in public DNS today

All read 2026-09-06 with `dig +short`, quoted verbatim.

| Query | Answer |
|---|---|
| `TXT stephens.page` | `"v=spf1 include:spf.mandrillapp.com include:_spf.google.com ?all"` and `"google-site-verification=ThkbDIfF9kU8LsZ-9cM3PK8Ux3S7cVmuyV8t82atjUE"` |
| `MX stephens.page` | `1 aspmx.l.google.com.`, `5 alt1.aspmx.l.google.com.`, `5 alt2.aspmx.l.google.com.`, `10 alt3.aspmx.l.google.com.`, `10 alt4.aspmx.l.google.com.` |
| `TXT _dmarc.stephens.page` | `"v=DMARC1; p=none"` |
| `TXT resend._domainkey.stephens.page` | `"p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDOsvH8BPJeNg2vgLU7fzTe0HfSXXztx028cLfhHcED72rgbVtBmkJcZntIRfUXLxv0RBe7sWWQyeQ0u2dudnUWhhX2HDRFOPRIxhmR3SAvc/u4JBnSon4UI/vyMnX2Jzrk3TwoF/sQRDcZdffNe9yNke5hkVHGR+VqoeYu0ZsN8QIDAQAB"` |
| `TXT send.stephens.page` | `"v=spf1 include:amazonses.com ~all"` |
| `MX send.stephens.page` | `10 feedback-smtp.us-east-1.amazonses.com.` |
| `NS stephens.page` | `alexa.ns.cloudflare.com.`, `jasper.ns.cloudflare.com.` |
| `A stephens.page` | `68.183.62.24` |
| `TXT thereish.app` | *(empty — no TXT records)* |
| `MX thereish.app` | *(empty — no MX records)* |
| `TXT _dmarc.thereish.app` | *(empty)* |
| `TXT resend._domainkey.thereish.app` | *(empty)* |
| `NS thereish.app` | `curitiba.ns.porkbun.com.`, `fortaleza.ns.porkbun.com.`, `maceio.ns.porkbun.com.`, `salvador.ns.porkbun.com.` |

Four observations, stated as observations:

- The Resend DKIM key is published at the selector `resend._domainkey`, and its value begins `MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQ` — the SubjectPublicKeyInfo prefix of a **1024-bit** RSA key. AWS's own default for Easy DKIM is 2048-bit ("Amazon SES automatically adds a 2048-bit DKIM key to every email", [Easy DKIM](https://docs.aws.amazon.com/ses/latest/dg/send-email-authentication-dkim-easy.html)), so this key length is Resend's choice, not SES's default. Note also that Easy DKIM asks for **three CNAME records**, whereas Resend publishes **one TXT key** — Resend holds the private key rather than delegating the selector to AWS.
- The apex SPF (`include:spf.mandrillapp.com include:_spf.google.com ?all`) does **not** include `amazonses.com`. It does not have to: SPF is checked against the envelope return-path, which Resend puts on `send.stephens.page`, and that subdomain's SPF does include it. DMARC then passes on **relaxed SPF alignment** (organizational-domain match between `send.stephens.page` and `stephens.page`) or on DKIM alignment via `d=stephens.page`.
- The apex SPF ends in `?all` (neutral), not `~all` or `-all`. Neutral tells receivers nothing about unlisted senders. `_dmarc.stephens.page` is `p=none` with no `rua=`, so no aggregate reports are being collected anywhere.
- **`thereish.app` has no mail DNS of any kind today** — no SPF, no MX, no DMARC, no DKIM selector. Whichever route is chosen, records get added there from zero.

### 1c. Documented versus inferred — the precise answer

| Claim | Status |
|---|---|
| Resend uses AWS as a "hosting and sending provider" | **Documented**, in Resend's own words, on its subprocessors page |
| Resend's per-domain return-path DNS points at an SES feedback endpoint | **Documented** in Resend's troubleshooting doc, and **observed** verbatim in `send.stephens.page` and `send.resend.com` |
| `include:amazonses.com` in the return-path SPF means SES IPs are doing the sending | **Strong inference, not a vendor statement.** `amazonses.com` resolves to `"v=spf1 ip4:199.255.192.0/22 … ip4:98.77.0.0/16 -all"` — AWS's SES egress ranges. An SPF include only authorises those IPs; it does not itself prove every message traverses them. Combined with the SES-specific `feedback-smtp.<region>.amazonses.com` MX, which exists only to receive SES bounce and complaint mail, the inference is about as strong as public DNS can make it |
| Resend's four regions are AWS regions | **Inference** from the codes (`us-east-1`, `eu-west-1`, `sa-east-1`, `ap-northeast-1`); the regions page never writes "AWS" |
| Resend is *only* SES, with no other sending path | **Not found**, and not established. Nothing rules out other transports for other traffic, and the CNAME migration for post-August-2026 domains suggests the mapping is being abstracted |
| Resend publishes SES as a status-page dependency | **No** — its status page lists no upstream provider |

So: **the honest answer to "isn't Resend built on SES anyway?" is "yes for the sending leg, as far as any outside observer can establish — Resend names AWS as a sending provider, and the DNS it asks you to publish is SES's own custom-MAIL-FROM shape."** What Resend adds on top of SES is not the SMTP path: it is the dashboard, the logs and event timeline, the API ergonomics, idempotency keys, webhooks via Svix, template rendering, contacts and suppression management, and — crucially for deliverability — a *shared reputation pool that Resend polices*, versus an AWS account whose reputation is entirely yours.

---

## 2. Amazon SES for this use

### 2a. The two interfaces

**SES v2 API.** `SendEmail` is `"POST /v2/email/outbound-emails HTTP/1.1"` with `Content-type: application/json`, against a regional endpoint of the form `email.<region>.amazonaws.com` ([SendEmail](https://docs.aws.amazon.com/ses/latest/APIReference-V2/API_SendEmail.html), [endpoints](https://docs.aws.amazon.com/general/latest/gr/ses.html)). The `Content` field takes exactly one of three shapes: `"Simple – A standard email message"`, `"Raw – A raw, MIME-formatted email message"`, `"Templated – A message that contains personalization tags"`. The response is `{"MessageId": "string"}`. Documented errors worth handling include `MessageRejected`, `MailFromDomainNotVerifiedException`, `TooManyRequestsException`, `SendingPausedException` and `AccountSuspendedException`. The API reference pages do **not** textually state SigV4 as the signing method (**not found** on both [SendEmail](https://docs.aws.amazon.com/ses/latest/APIReference-V2/API_SendEmail.html) and [Welcome](https://docs.aws.amazon.com/ses/latest/APIReference-V2/Welcome.html)); SigV4 is the AWS-wide default and is what the Elixir adapters implement (§5).

**SMTP.** Endpoints are `email-smtp.<region>.amazonaws.com`, with the caveat that "SMTP endpoints are not currently available in Africa (Cape Town), Asia Pacific (Hyderabad), … Canada West (Calgary), Asia Pacific (Malaysia)" ([endpoints](https://docs.aws.amazon.com/general/latest/gr/ses.html)). "Amazon SES SMTP endpoint requires that all connections be encrypted using Transport Layer Security (TLS)… supports two mechanisms… STARTTLS and TLS Wrapper": STARTTLS on "port 25, 587, or 2587", TLS Wrapper on "port 465 or 2465" ([SMTP connect](https://docs.aws.amazon.com/ses/latest/dg/smtp-connect.html)). SMTP credentials are a distinct artefact — "Your SMTP password is different from your AWS secret access key" — created through IAM or derived from an existing secret access key by a documented HMAC-SHA256 algorithm, and "Don't use temporary AWS credentials to derive SMTP credentials" ([SMTP credentials](https://docs.aws.amazon.com/ses/latest/dg/smtp-credentials.html)). They are region-specific.

Note for a DigitalOcean droplet: DO blocks outbound 25, 465 and 587 (§4), which leaves **2587 (STARTTLS)** and **2465 (TLS Wrapper)** as the usable SES SMTP ports, or the HTTPS API — which is why an API adapter is the low-friction choice here.

### 2b. From zero to a first send

The path is: create an AWS account → create an IAM identity with SES send permissions (an IAM user with an access key for a long-lived server, or an instance role if the app ran on EC2 — it does not; it runs on a DigitalOcean droplet, so it is a static access key or nothing) → optionally derive SMTP credentials from that key → create a **domain identity** for `thereish.app` and publish the DKIM CNAMEs → optionally configure a custom MAIL FROM subdomain → **request production access** → send.

**The sandbox is the real gate.** A new SES account is sandboxed: "You can only send mail to verified email addresses and domains, or to the Amazon SES mailbox simulator"; "You can send a maximum of 200 messages per 24-hour period"; "You can send a maximum of 1 message per second" ([request production access](https://docs.aws.amazon.com/ses/latest/dg/request-production-access.html), corroborated by the quota table on the [endpoints page](https://docs.aws.amazon.com/general/latest/gr/ses.html): "Sending quota | Each supported Region: 200 per 24 hours", "Sending rate | Each supported Region: 1 per second").

For the *operator notice* specifically, the sandbox is not actually a blocker: the recipient is one person, whose address can simply be verified. It **is** a blocker for ADR-0007 magic links, which go to arbitrary player addresses.

**Requesting production access** is done in the console or with `aws sesv2 put-account-details --production-access-enabled …`. On timing AWS says only: "The AWS Support team provides an initial response to your request within 24 hours." *Initial response* is not *approval*, and no SLA for approval is given. **Post-sandbox quota levels are not published as fixed numbers** — "this number varies based on your specific use case" (**not found**: any concrete initial production quota).

Other quotas that matter: max message size "10 MB per message" via the v1 API and "40 MB per message" via v2 or SMTP; "50 recipients per message"; "10,000 identities per AWS Region"; 10,000 configuration sets ([quotas](https://docs.aws.amazon.com/ses/latest/dg/quotas.html)).

### 2c. Domain identity, DKIM, SPF, DMARC

**Easy DKIM.** SES generates the keypair and you publish "the three CNAME records that appear in this section… to your DNS provider"; the default key is 2048-bit, overridable to `RSA_1024_BIT`; BYODKIM accepts a private key where the "private key length must be at least 1024 bits and up to 2048-bits"; "Changes to these settings can take up to 72 hours to propagate" ([Easy DKIM](https://docs.aws.amazon.com/ses/latest/dg/send-email-authentication-dkim-easy.html), [creating identities](https://docs.aws.amazon.com/ses/latest/dg/creating-identities.html)).

**SPF.** With no custom MAIL FROM, "in SES, SPF is implicitly set up for you" — the envelope sender lives under `amazonses.com`, which passes SPF but does **not align** with `thereish.app`. To get aligned SPF you configure a **custom MAIL FROM** subdomain, and then "SES requires you to publish an MX record so that your domain can receive the bounce and complaint notifications" plus "an SPF (type TXT) record"; "you must publish exactly one MX record to the DNS server of your MAIL FROM domain. If the MAIL FROM domain has multiple MX records, the custom MAIL FROM setup with Amazon SES will fail" ([MAIL FROM](https://docs.aws.amazon.com/ses/latest/dg/mail-from.html), [SPF](https://docs.aws.amazon.com/ses/latest/dg/send-email-authentication-spf.html)). Those two records are precisely what §1b found on `send.stephens.page`.

**DMARC.** SES's own example is `_dmarc.example.com` → `"v=DMARC1;p=quarantine;rua=mailto:my_dmarc_report@example.com"`; "SES uses a strict DKIM policy by default" and relaxed SPF alignment by default ([DMARC](https://docs.aws.amazon.com/ses/latest/dg/send-email-authentication-dmarc.html)).

### 2d. Regions

For a droplet in New York, `us-east-1` (N. Virginia) is the nearest SES region; its API endpoint is `email.us-east-1.amazonaws.com`, SMTP `email-smtp.us-east-1.amazonaws.com`, DKIM domain `dkim.amazonses.com`, feedback `feedback-smtp.us-east-1.amazonses.com`, click/open tracking `r.us-east-1.awstrack.me` ([endpoints](https://docs.aws.amazon.com/general/latest/gr/ses.html)). Identities, SMTP credentials, configuration sets and quotas are **all per-region** — a domain verified in `us-east-1` is not verified in `eu-west-1`.

### 2e. Pricing, as of 2026-09-06

Two independent fetches of [aws.amazon.com/ses/pricing](https://aws.amazon.com/ses/pricing/) returned:

| Line | Price as printed |
|---|---|
| À la carte, outbound email | "$0.10 / 1,000 emails" |
| À la carte, inbound email | "$0.10 / 1,000 emails" |
| Email Validation | "$0.01 per validation" |
| Essentials tier | "$0.16 per 1,000 emails" (0–10M/mo); "$0.14" (10–100M); "$0.11" (>100M) |
| Pro tier | "$0.22 per 1,000 emails" (0–10M/mo); "$0.17" (10–100M); "$0.12" (>100M) |
| Enterprise tier | "$0.23 per 1,000 emails" (0–10M/mo); "$0.18" (10–100M); "$0.13" (>100M) |
| Attachment data | "$0.12 per GB of attachment data sent" |
| Dedicated IPs — Standard / BYOIP | "$24.95 / month / IP" |
| Dedicated IPs — Managed | "$15 / month / account" |
| Mail Manager — Email Processing | "$0.15 / 1,000 emails" |
| Virtual Deliverability Manager | "$1,250 / month" |

**Free tier: essentially gone.** The only free-usage language on the SES pricing page is the account-wide credit — "New AWS customers will receive up to $200 in AWS Free Tier credits, which can be applied towards eligible AWS services", described elsewhere as available for six months after account creation and usable within twelve. The historical "62,000 free emails per month when sent from an EC2 instance" and the 3,000-message trial were **not found** on the current pricing page, and SES is **not listed** among the services on [aws.amazon.com/free](https://aws.amazon.com/free/?all-free-tier.q=ses). Treat SES as having **no standing free tier in 2026**.

**Not fully resolved:** the pricing page shows both an "à la carte" $0.10/1,000 outbound line *and* an Essentials/Pro/Enterprise tier table starting at $0.16/1,000. The precise relationship between the two — whether the tiers are opt-in bundles that supersede à la carte, and which applies by default to a bare new account — is **not clear from the fetched page text** and should be confirmed in the console before relying on either number. Both are quoted above so neither is lost.

### 2f. Events, suppression, VDM

**Configuration sets and event destinations.** A configuration set attaches to a send and routes events. Event types: Send, Delivery, Bounce, Complaint, Reject, Open, Click, Rendering Failure, Delivery Delay, Subscription. Destinations: Amazon SNS, Kinesis Data Firehose, CloudWatch, EventBridge ([event publishing](https://docs.aws.amazon.com/ses/latest/dg/event-publishing.html)). There is **no built-in HTTP webhook**: to get a bounce into Phoenix you publish to SNS and subscribe an HTTPS endpoint, which means implementing SNS subscription confirmation and message-signature verification yourself — that is the single largest piece of extra work versus a provider that POSTs JSON to a URL.

**Account-level suppression list.** "If you started using Amazon SES after November 25, 2019, your account uses the account-level suppression list by default for both bounces and complaints." "Only hard bounces are added to your account-level suppression list." "If your account's ability to send email is paused, SES automatically deletes the addresses in your account-level suppression list after 90 days." "To bulk add or remove addresses, you must have production access" ([suppression list](https://docs.aws.amazon.com/ses/latest/dg/sending-email-suppression-list.html)).

**Virtual Deliverability Manager** "is an Amazon SES feature that helps you enhance email deliverability by providing insights into your sending and delivery data", with an "SES deliverability" set (dashboard and advisor) and a "Global deliverability" set that "extends your visibility beyond Amazon SES" with campaign analytics, inbox placement testing and blocklist monitoring ([VDM](https://docs.aws.amazon.com/ses/latest/dg/vdm.html)). The doc page states no price; the pricing page's "$1,250 / month" line is the only figure found. At a few emails a week this is irrelevant, and it is named here only so it is not mistaken for something a hobby account should turn on.

---

## 3. Resend for this use

**Pricing** ([resend.com/pricing](https://resend.com/pricing)):

| Tier | Price | Volume | Domains | Notes |
|---|---|---|---|---|
| Free | $0 | "100 emails a day", "3,000" per month | "3 domains" | "30-day data retention", "10,000 automation runs" |
| Pro | "$20/mo" | "50,000" per month | "10 domains" | "No daily email limit", "100 AI credits / mo" |
| Scale | "$90/mo" → "$1,150/mo" | "100,000" → "2,500,000" per month | "1,000 domains" | "500 AI credits / mo" |
| Enterprise | "Custom" | "3M+ emails/month" | — | "99.99% uptime SLA", "Dedicated CSM", "Single Sign-On" |

**API.** `Authorization: Bearer re_xxxxxxxxx`; a `User-Agent` header is required or the request 403s. The send body takes `from`, `to` (string or array, max 50), `subject`, and optionally `html`, `text`, `react`, `cc`, `bcc`, `reply_to`, `scheduled_at`, `headers`, `topic_id`, `attachments`, `tags`, `template` ([send email](https://resend.com/docs/api-reference/emails/send-email)). Batch: "Trigger up to 100 batch emails at once" ([send batch](https://resend.com/docs/api-reference/emails/send-batch-emails)). Idempotency: an `Idempotency-Key` header (`Resend-Idempotency-Key` over SMTP), "up to 256 characters and must be unique per API request", "kept in the system for 24 hours" ([idempotency keys](https://resend.com/docs/dashboard/emails/idempotency-keys)). Rate limit: "The default maximum rate limit is 10 requests per second per team" ([API introduction](https://resend.com/docs/api-reference/introduction)).

**SMTP** is also offered: host `smtp.resend.com`, ports "25, 465, 587, 2465, 2587", username `resend`, password the API key ([send with SMTP](https://resend.com/docs/send-with-smtp)) — the same 2465/2587 escape hatches SES offers, for the same reason.

**Domain verification** is per-domain: add the domain, pick a region, publish the records the dashboard shows, and the domain moves through `not_started` → `pending` → `verified` (with `partially_verified`, `partially_failed`, `failed` and `temporary_failure` as other terminal or transient states) ([manage domains](https://resend.com/docs/dashboard/domains/manage-domains)).

**Can the verified `stephens.page` send for Thereish?** Only by sending `From:` an address *at that domain* — e.g. `thereish@stephens.page`. A verified domain authorises sending from addresses under that domain; it does not authorise a different domain. **Sending `From: something@thereish.app` requires `thereish.app` to be added and verified separately.** The free tier's "3 domains" makes that free. (A per-domain statement to this effect was not located as a single quotable sentence — **not found** — but it follows directly from the verification model being keyed on the domain, and from `thereish.app` today having no Resend DKIM selector at all.)

There is a real design question hiding here: an operator notice sent `From: notices@stephens.page` to the operator's own inbox needs no new domain and no new reputation. A magic link sent to a *player* should come from `thereish.app`, because that is the name on the page they just used. Those two needs can be met at different times.

**Webhooks** cover bounces and complaints directly: `email.bounced`, `email.clicked`, `email.complained`, `email.delivered`, `email.delivery_delayed`, `email.failed`, `email.opened`, `email.received`, `email.scheduled`, `email.sent`, `email.suppressed`, plus `domain.*`, `contact.*` and `suppression.added` / `suppression.removed` ([webhook event types](https://resend.com/docs/dashboard/webhooks/event-types)). Delivery is via Svix (listed as a subprocessor), i.e. signed HTTP POST to a URL — a Phoenix controller and a signature check, no SNS handshake.

**DMARC guidance** from Resend: start at `v=DMARC1; p=none; rua=mailto:dmarcreports@example.com;`, move to `quarantine`, then `reject`; "It's a best practice to use `quarantine` or `reject`, but only do this once you know your messages are delivering and fully passing DMARC" ([DMARC](https://resend.com/docs/dashboard/domains/dmarc)).

---

## 4. Other production-grade options

Prices as printed on each vendor's own pricing page, 2026-09-06.

| Provider | Free tier | Cheapest paid | API / SMTP | Note |
|---|---|---|---|---|
| **Postmark** | "$0/month" — "100 emails/month", "Never expires or runs out" | Basic "$15/month" for "10,000 emails/month", overage "$1.80 per 1,000 emails"; Pro "$16.50/month"; Platform "$18/month" | Both | Separates transactional from bulk at the infrastructure level: Message Streams are "parallel but completely separate sending infrastructures" so "transactional and marketing emails never mix" ([pricing](https://postmarkapp.com/pricing)). The strongest transactional-deliverability reputation of the list, at the highest per-message price |
| **Mailgun** | "$0/mo", "100 emails/day included" | Basic "Starting at $15/mo", "10,000 emails/mo included"; Foundation "$35/mo", "50,000 emails/mo" | Both | Long-standing, log retention improves with tier ([pricing](https://www.mailgun.com/pricing/)) |
| **SendGrid (Twilio)** | **None.** "Free trial lets you send 100 emails/day for 60 days" | "Essentials plan starts at $19.95 per month"; "Exact pricing depends on email send volume, features" | Both | `sendgrid.com/en-us/pricing` now redirects to Twilio — "SendGrid ❤️ Twilio. We're finally moving in together on Twilio.com!". The perpetual free plan is gone ([Twilio SendGrid pricing](https://www.twilio.com/en-us/products/email-api/pricing)) |
| **Brevo** | "you can start sending up to 300 emails per day" | Starter "From 5,000 emails per month" — **exact dollar figure not found** on Brevo's page (it renders behind a JS volume selector) | Both | "All Brevo plans give you access to transactional email features, including RESTful APIs, SMTP, outbound webhooks, unlimited log retention" — but transactional and marketing share one monthly meter ([pricing](https://www.brevo.com/pricing/)) |
| **Mailtrap** | "$0/month", "4,000 emails" monthly with a "150 emails/day limit", 1 domain, 3 days of logs | Basic "Starting at $15/month for 10,000 emails" | Both | Unusual value here: Mailtrap's *testing* product is the standard way to inspect mail in staging, and the same account also sends. Business "$85/month for 100,000 emails" ([pricing](https://mailtrap.io/pricing/)) |
| **SparkPost / Bird** | "$0" — "1,000 emails / month", "No credit card · 50/day cap" | Startup "from $15 / month", "50K to 100K emails / month" ($0.30/1,000, overage $0.90/1,000); Growth "from $80 / month" | Both | SparkPost is no longer standalone: `sparkpost.com` redirects to Bird, which says "SparkPost, the engine behind roughly 40% of the world's commercial email, is now Bird Email." Pricing is published, not sales-gated: "Every rate below is the published list price" ([Bird email pricing](https://bird.com/products/email/pricing)) |
| **Mailjet** | "6,000 emails/month" with a "200 emails per day" cap | Starter "$9/month" for "8,000 emails/month", no daily cap; Essential "$17/month" for "15,000"; Premium "$27/month" | Both | Cheapest paid entry point in the table; "10% discount" annually ([pricing](https://www.mailjet.com/pricing/)) |
| **Amazon SES** | No standing free tier (§2e) | "$0.10 / 1,000 emails" à la carte / "$0.16 per 1,000" Essentials | Both | Cheapest per message by a wide margin; most assembly required |

### Self-hosting on the droplet: not viable

DigitalOcean is explicit:

> "SMTP ports 25, 465, and 587 are blocked on Droplets to prevent spam and other abuses on our platform."
> "This block applies to all Droplets by default and includes traffic passing through a Reserved IP address."
> "To send mail from services hosted on DigitalOcean, we recommend using a third-party email as a service provider."

([Why is SMTP blocked?](https://docs.digitalocean.com/support/why-is-smtp-blocked/)). Whether DO will unblock those ports on request is **not stated on that page** (not found). DO's Acceptable Use Policy separately requires that "You will not take any action which directly or indirectly results in any of our IP addresses being listed on any abuse database (e.g., Spamhaus)" and that a complaints address such as `abuse@yourdomain.com` be published and monitored ([AUP](https://www.digitalocean.com/legal/acceptable-use-policy)).

A Postfix + OpenDKIM install on the droplet therefore cannot deliver directly to Gmail on port 25 at all. Even if the block were lifted, the substance of the problem remains: a single cloud IP with no sending history, in a range mail providers treat with suspicion, needing forward-confirmed reverse DNS (a PTR record DO controls), TLS, DKIM signing, a bounce-handling path, and someone to notice when it stops. Running Postfix purely as a *relay* to one of the providers above is possible but buys nothing over calling that provider's API directly from Elixir — it adds a daemon, a queue and a spool to babysit in exchange for the SMTP protocol.

**Self-hosting outbound mail from this droplet is off the table.** It is worth stating once so it does not get re-litigated at 2 a.m.

---

## 5. Elixir integration

**Swoosh** is at "1.28.0", "Aug 23, 2026" ([hex.pm/packages/swoosh](https://hex.pm/packages/swoosh)); installation snippet `{:swoosh, "~> 1.28"}`; it requires Elixir 1.16+ / OTP 26+. Its provider adapters, as listed in the README:

> SMTP, Mua, SendGrid, Brevo, Sendmail, Mandrill, Mailgun, MailerSend, Mailjet, MsGraph, Postmark, SparkPost, Amazon SES, Amazon SES (ExAws), Customer.io, Dyn, Scaleway, SocketLabs, Gmail, MailPace, SMTP2GO, ProtonBridge, Mailtrap, Mailpit, ZeptoMail, Postal, Lettermint, **Resend**, Azure Communication Services, AhaSend, TurboSMTP, Loops, PostUp

plus local and testing adapters `Swoosh.Adapters.Local`, `Swoosh.Adapters.Test`, `Swoosh.Adapters.Sandbox`, `Swoosh.Adapters.Mailpit` ([README](https://github.com/swoosh/swoosh/blob/main/README.md)). **Every provider in §3 and §4 has a first-party Swoosh adapter**, so the vendor choice does not constrain the Elixir code beyond a config line.

**`Swoosh.Adapters.AmazonSES`** — "An adapter that sends email using the Amazon Simple Email Service (SES) **Query API**." It uses the **`SendRawEmail`** action against API version `2010-12-01` — the SES **v1** Query API, not SES v2. It requires `:gen_smtp` (`~> 1.0`) in addition to Swoosh, because it builds the raw MIME message itself, and the doc warns: "If Swoosh was compiled prior to `:gen_smtp` being installed, it may be necessary to force a recompilation" (`mix deps.compile swoosh --force`). `required_config` is `[:region, :access_key, :secret]`; `:security_token`, for STS temporary credentials, is a *provider option* rather than a config key. Swoosh implements SigV4 itself — `AWS4-HMAC-SHA256`, its own `generate_signature/4` — and the doc is explicit that "This adapter does not depend on ExAws" ([Swoosh.Adapters.AmazonSES](https://swoosh.hexdocs.pm/Swoosh.Adapters.AmazonSES.html), [source](https://github.com/swoosh/swoosh/blob/main/lib/swoosh/adapters/amazon_ses.ex)). A parallel `Swoosh.Adapters.ExAwsAmazonSES` exists for apps already carrying ExAws.

Two things follow. First, choosing SES via Swoosh means adding `:gen_smtp` — a MIME/SMTP library — even though no SMTP connection is made. Second, it means running against SES's **v1 Query API**, so the v2 request shape in §2a is not what the wire will carry; the 10 MB v1 message-size limit applies rather than v2's 40 MB, which is irrelevant here but worth knowing.

**`Swoosh.Adapters.Resend`** — in-tree since Swoosh 1.20.0. "An adapter that sends email using the Resend API." Config is just `adapter: Swoosh.Adapters.Resend` and `api_key: "re_123456789"`. "This adapter requires an API Client. Swoosh comes with Hackney, Finch and Req out of the box." It exposes Resend's own features as provider options — `tags`, `scheduled_at`, `idempotency_key`, `template` — supports `deliver_many/2` mapped onto the batch endpoint ("The batch endpoint has a maximum of 100 emails per request and does not support scheduled_at or attachments"), and supports inline CID images ([Swoosh.Adapters.Resend](https://swoosh.hexdocs.pm/Swoosh.Adapters.Resend.html)). **No extra dependency beyond an HTTP client the app already has** — `finch 0.23.0` is already in `mix.lock` via Req.

**The `resend` hex package** is a separate, community-maintained SDK. Resend's own Elixir guide says of it: "This guides utilizes an open source library contributed by a community member. It's not developed, maintained, or supported by Resend directly," with `{:resend, "~> 0.4.0"}` ([send with Elixir](https://resend.com/docs/send-with-elixir)); latest stable 0.4.5 (2025-12-01), with a 1.0.0-rc.3 prerelease, maintained by an individual (`jtormey`, `elixir-saas/resend-elixir`) rather than Resend's own org. It *does* ship its own `Resend.Swoosh.Adapter`, so there are two routes to the same API — but since Swoosh now carries the adapter in-tree, this package is not needed.

**Other adapters' requirements**, for completeness: Postmark `[:api_key]` and Sendgrid `[:api_key]` need no extra deps; Brevo `[:api_key]` needs none and supports `deliver_many/2`; Mailgun `[:api_key, :domain]` needs `Plug` and `multipart`; Mailjet `[:api_key, :secret]` needs `Plug`; the generic SMTP adapter `[:relay]` needs `gen_smtp` (`~> 0.13 or ~> 1.0`).

**ExAws.SES** is at "2.4.1", released "Mar 23, 2022" ([hex.pm/packages/ex_aws_ses](https://hex.pm/packages/ex_aws_ses)), with a last GitHub commit of 2023-10-17 — dormant for roughly three years. It still gets ~5,500 downloads a week, so it works, and its API is mixed (core `send_email`/`send_raw_email` on the Query API; templates, contacts, suppression and `send_email_v2` on SES v2). It is not an actively developed path and there is no reason to prefer it over the in-tree Swoosh adapter.

**Phoenix.** Current Phoenix is **1.8.13** (2026-08-25); there is no 1.9. `mix phx.new` ships a Swoosh mailer **by default** — it generates `lib/<app>/mailer.ex`, adds `{:swoosh, "~> 1.16"}` and `{:req, "~> 0.5"}`, wires `Swoosh.Adapters.Local` in dev with the `/dev/mailbox` preview and `Swoosh.Adapters.Test` in test — and the flag to suppress all of it is `--no-mailer`, "do not generate Swoosh mailer files" ([Mix.Tasks.Phx.New](https://phoenix.hexdocs.pm/Mix.Tasks.Phx.New.html)). This repo has `{:req, "~> 0.5"}` but no `:swoosh`, which is exactly the `--no-mailer` shape: adding a mailer means adding the dep and writing `MeaningGame.Mailer` by hand rather than un-deleting generated files.

`mix phx.gen.auth` "generates email based authentication, which assumes the user who owns the email address has control over the account", and is **magic-link/passwordless by default in 1.8** — the guide's sections are "Log in with magic links" and "Opt-in password authentication", and the 1.8 changelog records "Introduce magic links (passwordless auth) and 'sudo mode' … while simplifying the generated structure." That matches ADR-0007 exactly. The task doc says **nothing** about Swoosh or mailer configuration (**not found** on [Mix.Tasks.Phx.Gen.Auth](https://phoenix.hexdocs.pm/Mix.Tasks.Phx.Gen.Auth.html)) because it assumes the mailer `phx.new` normally generates is already there — which, for this `--no-mailer` app, it is not. **Running `phx.gen.auth` here without first adding Swoosh will produce code that references a Mailer that does not exist.**

**HTTP client.** Swoosh "comes with `Swoosh.ApiClient.Hackney` configured by default" but "accepts Finch and Req out-of-the-box"; all three are optional deps, none pulled in transitively. A `phx.new` app ships Req, which this repo already has (`req 0.7.4`, `finch 0.23.0` in `mix.lock`), so the API client is a config line and no new dependency. `config :swoosh, :api_client, false` disables it entirely, which is what the Local, Test and SMTP adapters want.

**Testing.** `Swoosh.Adapters.Test` captures deliveries as messages to the test process, asserted with `Swoosh.TestAssertions` (`assert_email_sent/1`, `refute_email_sent/0`, `assert_emails_sent/0`); global-mode tests cannot be `async: true`. `Swoosh.Adapters.Local` stores mail in an in-memory storage driver (`Storage.Memory` by default) rendered by **`Plug.Swoosh.MailboxPreview`** — note the module name; it is *not* `Swoosh.Plug.MailboxPreview` — conventionally forwarded at `/dev/mailbox`. `Swoosh.Adapters.Sandbox` is what the docs recommend for LiveView and end-to-end tests, and `Swoosh.Adapters.Mailpit` is the other non-sending option. This is the same in dev and test regardless of which production adapter is chosen — meaning **the vendor decision can be deferred past the point where the notice is written and tested**, because nothing in the notice's code or tests depends on it.

---

## 6. Deliverability essentials, whatever the vendor

**SPF** (RFC 7208), **DKIM** (RFC 6376) and **DMARC** — now **RFC 9989**, "Domain-Based Message Authentication, Reporting, and Conformance (DMARC)", Proposed Standard, published **May 2026**, which "Obsoletes" RFC 7489 and RFC 9091 ([datatracker RFC 9989](https://datatracker.ietf.org/doc/rfc9989/)). Anything citing RFC 7489 is now citing a superseded document.

**Gmail** ([Email sender guidelines](https://support.google.com/a/answer/81126)), effective 1 February 2024. For **all senders**: "Set up SPF or DKIM email authentication for your sending domains"; "Use a TLS connection for transmitting email"; "Ensure that sending domains or IPs have valid forward and reverse DNS records"; "Keep spam rates reported in Postmaster Tools below 0.3%"; format messages per RFC 5322. For **bulk senders (5,000+ messages a day)**, additionally: "Set up SPF **and** DKIM email authentication for your domain"; "Set up DMARC email authentication for your sending domain" — the enforcement policy "can be set to none"; "For direct email, the domain in the sender's From: header must be aligned with either the SPF domain or the DKIM domain"; and "Marketing messages and subscribed messages must support one-click unsubscribe".

**Yahoo** ([Sender best practices](https://senders.yahooinc.com/best-practices/)), also February 2024. All senders: "SPF or DKIM at a minimum"; "Keep your spam rate below 0.3%"; valid forward and reverse DNS; RFC 5321/5322 compliance. Bulk senders: "Implement both SPF & DKIM" plus "Publish a valid DMARC policy with at least p=none", and "Implement a functioning list-unsubscribe header, which supports one-click unsubscribe" where "The Post (RFC 8058) method is highly recommended". Yahoo's page does **not** mention TLS (not found).

**One-click unsubscribe does not apply here.** Both Google and Yahoo scope it to marketing and subscribed mail; RFC 8058's own framing is "Operators of broadcast marketing lists", and it makes "no explicit mention" of transactional messages ([RFC 8058](https://www.rfc-editor.org/rfc/rfc8058.html)). A magic-link login mail and a private operator notice are neither marketing nor subscription mail. Adding a `List-Unsubscribe` header to a login link would be actively wrong.

**Thereish is nowhere near the bulk threshold** — a few emails a week is four orders of magnitude below 5,000/day. But the bulk requirements are worth meeting anyway, because they are cheap (three DNS records) and because the *penalty* for failing SPF/DKIM alignment on a tiny volume is disproportionate: a login link that lands in spam is a broken feature, and with no volume there is no reputation to absorb the mistake. The concrete list for `thereish.app`, which has **no mail DNS today** (§1b):

1. DKIM — whatever the chosen vendor's records are (three CNAMEs for SES Easy DKIM; one TXT for Resend).
2. SPF on the return-path domain, aligned to `thereish.app` (SES: custom MAIL FROM; Resend: the `send.` subdomain it provisions).
3. `_dmarc.thereish.app` with at minimum `v=DMARC1; p=none; rua=mailto:…` — and note the **`rua=`**, which `_dmarc.stephens.page` currently lacks, meaning no aggregate reports are arriving anywhere today. Reports are the only way to find out something is misaligned before a user does.
4. A monitored reply-to or `abuse@` address, per DO's AUP.

**BIMI is optional** and out of scope: it requires DMARC at enforcement (`p=quarantine` or `p=reject`) — the BIMI Group's own tool "only validates the format of your BIMI record and your DMARC record being at enforcement" ([BIMI generator](https://bimigroup.org/bimi-generator/)) — plus an SVG Tiny PS logo and, for Gmail, a paid Verified Mark Certificate. For an operator notice and a login link there is no return on it. (Detailed BIMI requirement text could not be retrieved; the BIMI Group FAQ URL 404s — **not found**.)

---

## 7. Cost and effort at the two volumes that matter

Monthly cost, computed from the prices quoted above. "50/mo" is roughly the operator notice alone; "5,000/mo" is a Thereish that is genuinely being played and sending magic links.

| Route | 50 emails/mo | 5,000 emails/mo | Setup steps before first production send | Bounce handling |
|---|---|---|---|---|
| **Resend, existing account, `From: @stephens.page`** | $0 (free tier: 100/day, 3,000/mo) | $20/mo (Pro — free tier caps at 3,000/mo) | Add API key to the release env; `{:swoosh, "~> 1.28"}`; one config line. Zero DNS. | Signed webhook POST → one Phoenix controller |
| **Resend, `thereish.app` verified** | $0 | $20/mo | The above + add domain, pick `us-east-1`, publish the records the dashboard prints | Same |
| **Amazon SES** | $0.005 (à la carte) or $0.008 (Essentials) | $0.50 or $0.80 | AWS account; IAM user + access key; domain identity; 3 DKIM CNAMEs; custom MAIL FROM (MX + TXT); **production access request** (initial response ≤24 h, approval SLA not published); config set; SNS topic + HTTPS subscription. `{:swoosh, "~> 1.28"}` + `{:gen_smtp, "~> 1.0"}` | SNS: subscription confirmation handshake + signature verification, written by you |
| **Postmark** | $0 (100/mo free) | $15/mo (Basic, 10,000) | API token; add and verify domain (DKIM + return-path) | Webhook POST |
| **Mailjet** | $0 (6,000/mo free, 200/day) | $0 (within free tier) | API key/secret; verify domain | Webhook POST |
| **Bird (SparkPost)** | $0 (1,000/mo free, 50/day) | $15/mo (Startup) | API key; verify domain | Webhook POST |
| **Self-host Postfix on the droplet** | — | — | **Not possible**: DO blocks outbound 25/465/587 by default | — |

At 50/month, price is not a variable: every route is between $0 and one cent. At 5,000/month the spread is $0 to $20 — still not a variable for a hobby project. **Cost cannot decide this.** What differs by an order of magnitude is setup steps and the number of things that can be misconfigured.

**What breaks at 2 a.m., per route.** With Resend: the API returns a non-2xx, Swoosh returns `{:error, reason}`, and the dashboard's event log says why — one place to look, and the notice is a fire-and-forget side effect anyway. With SES the failure modes multiply: the account is still in the sandbox and the recipient was never verified (`MessageRejected`); the IAM key was rotated or the policy is wrong (`AccessDenied`); the custom MAIL FROM broke because a second MX record appeared on the subdomain, which AWS documents as an outright failure mode; bounce rate crossed a threshold and AWS paused sending (`SendingPausedException` / `AccountSuspendedException`); or the SNS subscription silently unconfirmed and bounces stopped arriving. None of these is exotic; all of them are things the operator would be diagnosing personally, at whatever hour, against CloudWatch rather than a timeline.

**Lock-in is near zero either way**, and this is the most useful fact in the whole document. Swoosh's adapter interface means switching vendors is a dependency line and a config block; `Swoosh.Adapters.Test` means the notice's tests never touch a vendor at all. The DNS records are per-vendor and take an hour to re-cut. There is no data to migrate — no contact lists, no templates worth preserving. **The decision is reversible, which means it does not need to be got right the first time.**

---

## What this implies

- **The premise of the question checks out.** Resend names AWS as a "sending provider" in its own subprocessor list, and the DNS it asks you to publish — `include:amazonses.com` on the return-path subdomain, `feedback-smtp.<region>.amazonses.com` as its single MX — is SES's documented custom-MAIL-FROM shape, visible right now on both `send.stephens.page` and Resend's own `send.resend.com`. Learning SES therefore does not add a *new* delivery infrastructure to the operator's life; it removes a layer from one he is already, indirectly, using. That reframes "learn SES" from *acquire a better system* to *see one layer lower*, which is a perfectly good reason and a different one.
- **What Resend actually sells is not the SMTP path.** It is the dashboard and searchable event log, HTTP webhooks instead of an SNS handshake, idempotency keys, no sandbox, no production-access ticket, and a shared sending reputation that Resend defends. SES gives none of those and gives instead: 60× lower unit cost that rounds to zero at this volume, a reputation that is entirely the operator's to build or ruin, configuration sets, VDM at $1,250/month, and everything assembled by hand.
- **SES's sandbox is the one hard schedule risk.** The operator notice can ship inside the sandbox today by verifying one recipient address. ADR-0007's magic links cannot — they go to arbitrary addresses, so production access must be granted first, and AWS commits only to "an initial response… within 24 hours" with no approval SLA. If magic links are ever wanted on a specific evening, that is the item that does not compress.
- **Self-hosting is closed.** DigitalOcean blocks outbound 25, 465 and 587 on all droplets by default and tells you to use a provider. That is not a preference to argue with.
- **The Elixir layer is genuinely vendor-neutral, and the two candidates are not equal work.** `Swoosh.Adapters.Resend` needs an API key and the Finch client already in `mix.lock`. `Swoosh.Adapters.AmazonSES` needs `:gen_smtp`, three AWS config keys, and runs against SES's older v1 Query API via `SendRawEmail`. Both are one config block. Dev and test use `Swoosh.Adapters.Local` and `Swoosh.Adapters.Test` regardless — so **the notice can be written, tested and reviewed before the vendor is chosen at all.**
- **Adding Swoosh is a prerequisite for ADR-0007 independent of the vendor question.** `mix phx.gen.auth` on Phoenix 1.8 is magic-link and passwordless by default, which is precisely what ADR-0007 asked for, but it assumes the mailer `mix phx.new` normally generates — and this app was generated without one. Whoever runs that generator will need `:swoosh` and a `MeaningGame.Mailer` in place first. Writing the operator notice now puts both there.
- **`thereish.app` has no mail DNS whatsoever today.** Whichever route is taken, SPF, DKIM and DMARC records get published there from zero — and `_dmarc.stephens.page` is currently `p=none` with no `rua=`, so no aggregate reports are being collected for the existing setup either. Adding `rua=` is a five-minute change with more deliverability value than any vendor choice in this document.
- **The two routes are not mutually exclusive, and nothing forces them to be chosen at the same time.** The notice and the magic link are different mails with different senders, different audiences and different dates. One can ride the existing Resend account from `@stephens.page` this week; the other needs a verified `thereish.app` and, on SES, a production-access grant.

## Recommendation

**Ship the notice on the existing Resend account behind `Swoosh.Adapters.Resend`, and treat SES as a separate, unhurried learning exercise pointed at `thereish.app` for the ADR-0007 magic links.** The notice is a one-recipient side effect that should cost an afternoon, not a weekend: with Resend it is `{:swoosh, "~> 1.28"}`, an API key in the release env, `From: notices@stephens.page` on an already-verified domain, zero new DNS, and a working dashboard to look at when it misbehaves — and Swoosh's `Test` and `Local` adapters mean the code and its tests are identical no matter what sends the mail later. Then, when the magic-link work under ADR-0007 actually begins, stand up SES properly against `thereish.app`: create the AWS account, publish the three Easy DKIM CNAMEs and the custom MAIL FROM MX and TXT, wire a configuration set to an SNS topic and an HTTPS endpoint, and **request production access early**, because that is the only step with a queue in front of it and AWS commits to nothing beyond a first response within 24 hours. Doing it in that order gets the learning without putting a sandbox exit on the critical path of a feature, and it costs nothing to abandon halfway: at fifty emails a month both routes are free, at five thousand the gap is $20, and Swoosh's adapter seam makes the whole choice a config line the operator can change twice before breakfast. The one thing worth doing immediately, independent of all of this, is adding `rua=` to `_dmarc.stephens.page` and publishing SPF, DKIM and DMARC on `thereish.app` — nothing else in this document improves deliverability as much per minute spent.

---

## Sources

All fetched or queried 2026-09-06.

**DNS (read live with `dig`, §1b):** `stephens.page`, `send.stephens.page`, `resend._domainkey.stephens.page`, `_dmarc.stephens.page`, `thereish.app`, `_dmarc.thereish.app`, `send.resend.com`, `_dmarc.resend.com`, `amazonses.com`, `spf.mandrillapp.com`.

**Resend**
- https://resend.com/legal/subprocessors
- https://resend.com/pricing
- https://resend.com/docs/dashboard/domains/introduction
- https://resend.com/docs/dashboard/domains/manage-domains
- https://resend.com/docs/dashboard/domains/regions
- https://resend.com/docs/dashboard/domains/dmarc
- https://resend.com/docs/knowledge-base/what-if-my-domain-is-not-verifying
- https://resend.com/docs/api-reference/introduction
- https://resend.com/docs/api-reference/emails/send-email
- https://resend.com/docs/api-reference/emails/send-batch-emails
- https://resend.com/docs/dashboard/emails/idempotency-keys
- https://resend.com/docs/dashboard/webhooks/introduction
- https://resend.com/docs/dashboard/webhooks/event-types
- https://resend.com/docs/send-with-smtp
- https://resend.com/docs/send-with-elixir
- https://resend.com/handbook/engineering/what-is-our-tech-stack
- https://resend-status.com/ (from https://status.resend.com)

**Amazon SES / AWS**
- https://aws.amazon.com/ses/pricing/
- https://aws.amazon.com/free/?all-free-tier.q=ses
- https://docs.aws.amazon.com/ses/latest/APIReference-V2/API_SendEmail.html
- https://docs.aws.amazon.com/ses/latest/APIReference-V2/Welcome.html
- https://docs.aws.amazon.com/general/latest/gr/ses.html
- https://docs.aws.amazon.com/ses/latest/dg/smtp-connect.html
- https://docs.aws.amazon.com/ses/latest/dg/smtp-credentials.html
- https://docs.aws.amazon.com/ses/latest/dg/request-production-access.html
- https://docs.aws.amazon.com/ses/latest/dg/quotas.html
- https://docs.aws.amazon.com/ses/latest/dg/creating-identities.html
- https://docs.aws.amazon.com/ses/latest/dg/send-email-authentication-dkim-easy.html
- https://docs.aws.amazon.com/ses/latest/dg/mail-from.html
- https://docs.aws.amazon.com/ses/latest/dg/send-email-authentication-spf.html
- https://docs.aws.amazon.com/ses/latest/dg/send-email-authentication-dmarc.html
- https://docs.aws.amazon.com/ses/latest/dg/event-publishing.html
- https://docs.aws.amazon.com/ses/latest/dg/vdm.html
- https://docs.aws.amazon.com/ses/latest/dg/sending-email-suppression-list.html

**Other providers and hosting**
- https://postmarkapp.com/pricing
- https://www.mailgun.com/pricing/
- https://www.twilio.com/en-us/products/email-api/pricing (from https://sendgrid.com/en-us/pricing)
- https://www.brevo.com/pricing/
- https://mailtrap.io/pricing/
- https://bird.com/products/email/pricing
- https://bird.com/en-es/products/email/sparkpost (from https://www.sparkpost.com/)
- https://www.mailjet.com/pricing/
- https://docs.digitalocean.com/support/why-is-smtp-blocked/
- https://www.digitalocean.com/legal/acceptable-use-policy

**Elixir / Phoenix**
- https://hex.pm/packages/swoosh
- https://github.com/swoosh/swoosh/blob/main/README.md
- https://swoosh.hexdocs.pm/Swoosh.Adapters.AmazonSES.html
- https://github.com/swoosh/swoosh/blob/main/lib/swoosh/adapters/amazon_ses.ex
- https://swoosh.hexdocs.pm/Swoosh.Adapters.Resend.html
- https://swoosh.hexdocs.pm/Swoosh.Adapters.Local.html
- https://hex.pm/packages/resend
- https://github.com/elixir-saas/resend-elixir
- https://hex.pm/packages/ex_aws_ses
- https://hex.pm/packages/phoenix
- https://phoenix.hexdocs.pm/Mix.Tasks.Phx.New.html
- https://phoenix.hexdocs.pm/Mix.Tasks.Phx.Gen.Auth.html

**Standards and sender guidelines**
- https://support.google.com/a/answer/81126
- https://senders.yahooinc.com/best-practices/
- https://datatracker.ietf.org/doc/rfc9989/
- https://www.rfc-editor.org/rfc/rfc8058.html
- https://bimigroup.org/bimi-generator/
