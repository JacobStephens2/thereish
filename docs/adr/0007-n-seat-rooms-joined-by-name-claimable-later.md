---
status: accepted
---

# Rooms are N-seat from the first line of code, joined by name alone, claimable by an account later

The game was designed for two players on a couch, but it is not essentially two-player: Thereish generalizes to a Jackbox-shaped group (everyone bridges the same Anchors, the Assayer grades the pairs, the stage shows who melded with whom). Decision (2026-09-02): the Game and Room hold **N seats, two by default** — a list, not a pair — because retrofitting N onto a two-seat model is a rewrite while choosing it now costs nothing. Stage 1's UI still builds two phones plus the stage.

Identity follows Jackbox, not SaaS: **joining a room takes only a name**; the seat holds a stable id and a device token. An **account exists only to claim a seat's history afterwards** — the per-person Chronicle view ("Jack tends to make potty-humor connections") is the whole reason accounts exist. Magic-link email first (Phoenix 1.8's generated auth is passwordless by default); Google sign-in later as a convenience. Accounts are post-couch-night; Stage 1's one obligation is stable seat ids an account can claim.

## Considered options

- **Two-seat model, generalize later**: simpler today, a rewrite tomorrow. Rejected.
- **Sign in before joining**: friction at the door kills party games, and a household couch game needs none of it. Rejected.

## Consequences

Chronicle rows reference seat ids, never accounts; an account maps to many seats. Group scoring rules (pairwise meld map vs. group centroid) remained open for the spec; settled by ADR-0010, which supersedes the pairwise sketch above — the Assayer grades every Bridge as one set, one Verdict per Attempt.
