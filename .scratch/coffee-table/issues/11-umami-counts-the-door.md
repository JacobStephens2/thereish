# 11: Umami counts the door

**What to build:** Jacob can see whether anyone played without asking. The root layout renders Umami's script tag — deferred, carrying the website id — when a script URL and a website id are both configured through runtime configuration, and nothing at all otherwise, so development and tests load nothing. The instance is the one already running on the server; the website is created in its dashboard by hand. No session replay, no other tracking. The deploy's key check and the boot line learn the two names so a missing pair is said out loud, and the key wizard can push them. Spec section: Umami.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] With `UMAMI_SCRIPT_URL` and `UMAMI_WEBSITE_ID` configured, every page's root layout carries the deferred script tag with the website id; with either missing, no tag renders
- [ ] `bin/deploy` and the boot line note the pair when absent; `bin/keys-to-server` lists both names with what they buy
- [ ] A controller test for the tag present and absent
- [ ] Jacob has created the website in Umami and the two values are on the server; the first page view shows in the dashboard
