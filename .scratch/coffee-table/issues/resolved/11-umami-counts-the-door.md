# 11: Umami counts the door

**What to build:** Jacob can see whether anyone played without asking. The root layout renders Umami's script tag — deferred, carrying the website id — when a script URL and a website id are both configured through runtime configuration, and nothing at all otherwise, so development and tests load nothing. The instance is the one already running on the server; the website is created in its dashboard by hand. No session replay, no other tracking. The deploy's key check and the boot line learn the two names so a missing pair is said out loud, and the key wizard can push them. Spec section: Umami.

**Blocked by:** None (can start immediately).

**Status:** resolved

- [x] With `UMAMI_SCRIPT_URL` and `UMAMI_WEBSITE_ID` configured, every page's root layout carries the deferred script tag with the website id; with either missing, no tag renders
- [x] `bin/deploy` and the boot line note the pair when absent; `bin/keys-to-server` lists both names with what they buy
- [x] A controller test for the tag present and absent
- [x] Jacob has created the website in Umami and the two values are on the server; the first page view shows in the dashboard

## Answer

1. Created website `thereish.app` in self-hosted Umami (`https://analytics.stephens.page`) with ID `2787e006-03df-4ad6-9451-9edf74553410` (no session replay).
2. Set `UMAMI_SCRIPT_URL=https://analytics.stephens.page/script.js` and `UMAMI_WEBSITE_ID=2787e006-03df-4ad6-9451-9edf74553410` in `/var/www/thereish.app/.env` on the VPS.
3. Recreated the `meaning-game-app` container; verified the boot warning is silent and the deferred script tag renders in production HTML.
4. Sent test pageview to `https://analytics.stephens.page/api/send` and verified the event recorded in `website_event` table in the Umami database.
