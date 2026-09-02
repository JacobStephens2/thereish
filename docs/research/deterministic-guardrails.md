# Deterministic guardrails around the three machine roles

Researched 2026-09-01 for the [design brief](../design-brief.md). Question: how can *deterministic* systems wrap the **Author** (builds Pages before play), the **Meter** (grades meaning-closeness live), and the **Scribe** (writes the Chronicle after play) so generated content is more consistent, with no second model in the loop? Three parts: (1) prose linting as a post-generation gate for the Scribe's voice, (2) deterministic legality checks for word-game clues in Elixir, (3) what each provider actually guarantees about output shape.

Method: every claim traces to a primary source fetched 2026-09-01 — official docs, the repos themselves (dates and licenses read through the GitHub API), and the hex.pm / npm / PyPI registry APIs. Vale 3.19.0 was downloaded into a scratch directory and run on a Scribe-like snippet to verify the CLI claims empirically (nothing was installed system-wide, nothing in this repo was touched). Secondary sources are labeled. Everything under [Signals for our design](#signals-for-our-design-inference) is inference.

---

## 1. Prose linting as a post-generation gate (Scribe)

### 1a. Vale — version and maintenance

| Fact | Source |
|---|---|
| Canonical repo is now **`vale-cli/vale`** (`errata-ai/vale` redirects); MIT; Go (`go 1.25.7` in `go.mod`); default branch `v3`; last push 2026-08-28; 6,053 stars | [GitHub API `repos/vale-cli/vale`](https://github.com/vale-cli/vale) |
| Latest release **v3.19.0, published 2026-08-26**; before it v3.18.0 (2026-08-20), v3.17.1 (08-05), v3.17.0 (07-31), v3.16.0 (07-29), v3.15.2 (07-23) — a release roughly every week this summer | [releases](https://github.com/vale-cli/vale/releases) |
| Single-binary release assets per platform: `vale_3.19.0_Linux_64-bit.tar.gz`, `_Linux_arm64`, `_macOS_arm64`, `_macOS_64-bit` | release assets, same page |
| Docs moved to **docs.vale.sh** (`vale.sh/docs/*` returns 301 to `docs.vale.sh/topics/*`) | observed on fetch |

### 1b. How custom styles are defined

From [docs.vale.sh/topics/styles](https://docs.vale.sh/topics/styles): a style is a folder under `StylesPath` holding YAML rule files (they "must end in `.yml`", not `.yaml`); `.vale.ini` activates styles per glob with `BasedOnStyles`. Every rule has `extends` (the check type, required) and `message` (required); optional `level` (`suggestion` | `warning` | `error`, default suggestion), `scope` (default `text`; e.g. `heading`, `sentence`), `link`, `limit`, `vocab`.

The eleven extension points, in the docs' own words:

| `extends:` | Purpose |
|---|---|
| `existence` | "Check for the presence of a specific regex pattern" |
| `substitution` | "Replace a regex pattern with a specific string" |
| `occurrence` | "Ensure regex pattern appears a specific number of times" |
| `repetition` | "Avoid repeating a regex pattern a specific number of times" |
| `consistency` | "Ensure regex pattern is used consistently" |
| `conditional` | "Check for regex pattern presence based on conditions" |
| `capitalization` | "Ensure regex pattern is capitalized in specific ways" |
| `metric` | "Check readability using custom formulas" |
| `spelling` | "Spell check using Hunspell-compatible dictionaries" |
| `sequence` | "Ensure regex pattern follows specific order; supports POS tagging" |
| `script` | "Run custom Tengo script to check content" |

Verbatim examples from the docs:

```yaml
# existence — docs.vale.sh/topics/styles
extends: existence
message: "Don't use end punctuation in headings."
link: https://docs.microsoft.com/en-us/style-guide/punctuation/periods
nonword: true
level: warning
scope: heading
action:
  name: edit
  params:
    - remove
    - '.?!'
tokens:
  - '[a-z0-9][.?!](?:\s|$)'
```

```yaml
# substitution — docs.vale.sh/checks/substitution
extends: substitution
message: Consider using '%s' instead of '%s'
level: warning
ignorecase: false
# swap maps tokens in form of bad: good
swap:
  abundance: plenty
  accelerate: speed up
```
Keys: `swap` ("A sequence of `observed: expected` pairs"; keys may be regex, e.g. `'(?:give|gave) rise to': lead to`; alternatives with `|`), `ignorecase`, `nonword` ("Removes the default word boundaries (`\b`)"), `exceptions`, `capitalize`.

```yaml
# metric — docs.vale.sh/checks/metric
extends: metric
message: 'Try to keep the Flesch-Kincaid grade level (%s) below 8.'
formula: |
  (0.39 * (words / sentences)) + (11.8 * (syllables / words)) - 15.59
condition: '> 8.0'
```
Formula variables: `blockquote`, `characters`, `complex_words`, `heading.h{n}`, `list`, `long_words`, `paragraphs`, `polysyllabic_words`, `pre`, `sentences`, `syllables`, `words`; conditions must use floats (`"== 8.0"`, not `"== 8"`).

**Vocabularies** ([docs.vale.sh/keys/vocabularies](https://docs.vale.sh/keys/vocabularies.md)): `<StylesPath>/config/vocabularies/<Name>/accept.txt` and `reject.txt`, enabled with `Vocab = Name`. Accept entries are "added to every exception list in all styles listed in `BasedOnStyles`" and become a substitution rule `Vale.Terms` that enforces exact casing; reject entries are "automatically added to an existence rule (`Vale.Avoid`) that will flag all occurrences as errors". Entries are case-sensitive regular expressions (`(?i)word` for case-insensitive).

Verified locally (Vale 3.19.0): a five-rule `Scribe` style (existence for AI-tell words and em dashes, a `substitution` for utilize→use, a `metric` capping `words > 40.0`, an existence regex for "not just X, it's Y") plus a `Chronicle` vocabulary with `reject.txt` all loaded and fired on a 48-word snippet, exit code 1.

### 1c. Packages — one Go binary for proselint, write-good, alex, Joblint, Microsoft, Google

Mechanism ([docs.vale.sh/keys/packages](https://docs.vale.sh/keys/packages.md)): `Packages = Google, write-good` in `.vale.ini`, then `vale sync`. A package may be "A name of a package hosted in the official Package Explorer", "a URL to an externally-hosted package", or a local `.zip`/directory; a package is style-only, config-only, or complete (`.vale.ini` + styles). The registry is `library.json` in [`vale-cli/packages`](https://github.com/vale-cli/packages) (MIT; 18 entries; last push 2026-08-28), which powers [vale.sh/explorer](https://vale.sh/explorer).

Provenance of the packages asked about (registry entry → hosting repo → license and last tag, from the GitHub API; rule counts from a local `vale sync`):

| Package | Registry description | Repo (all `errata-ai/*` URLs now redirect to `vale-cli/*`) | License | Latest tag | Rules |
|---|---|---|---|---|---|
| proselint | "A Vale-compatible implementation of Python's proselint linter" | vale-cli/proselint | BSD-3-Clause | v0.3.4, 2024-06-09 (push 2025-09-08) | 34 |
| write-good | "A Vale-compatible implementation of the write-good linter" | vale-cli/write-good | MIT | v0.4.1, 2024-06-09 (push 2025-05-23) | 8 |
| alex | "…the guidelines enforced by the alex linter: catch insensitive, inconsiderate writing" | vale-cli/alex | MIT | v0.2.3, 2024-11-02 | 11 |
| Joblint | "A Vale-compatible implementation of the Joblint linter" | vale-cli/Joblint | MIT | v0.4.1, 2021-04-07 | 17 |
| Microsoft | "…implementation of the Microsoft Writing Style Guide" | vale-cli/Microsoft | MIT | v0.15.1, 2026-08-04 | 47 |
| Google | "…implementation of the Google Developer Documentation Style Guide" | vale-cli/Google | MIT | v0.7.1, 2026-08-04 | 36 |
| Readability | "Vale-compatible implementations of many popular readability metrics" | vale-cli/readability | MIT | push 2022-10-31 | 7 |
| AiTells | "Flags the tells of AI-written prose: em-dash habits, epigrams, abstract-noun triads, clichés, and 13 more benchmarked rules" | krishnasunkam/vale-ai-tells | MIT | added to registry 2026-08-25 | 17 |

Also in the registry: Harper (added 2026-08-28), RedHat, AsciiDoc, AsciiDocDITA, Elastic, Salesforce, neighbor (inclusive language), Hugo, MDX.

Empirical: `Packages = proselint, write-good, alex, Joblint, Microsoft, Google, Readability, AiTells` → `vale sync` reported "Synced 8 package(s)" in about 3 s and all eight styles loaded together. Caveat: the ports are **subsets that lag upstream** — the proselint port has 34 rule files against 76 check modules in [amperser/proselint](https://github.com/amperser/proselint) and was last tagged 2024-06-09, while upstream shipped 0.16.0 on 2025-11-14.

### 1d. CLI, JSON output, short snippets

From [docs.vale.sh/topics/cli](https://docs.vale.sh/topics/cli): `--output=JSON` (also `line`, `CLI`, or a template), `--ext=.md` assigns an extension to stdin (`echo "This is Markdown" | vale --ext=.md`), `--no-exit` ("Do not return a non-zero exit code if there are errors"), `--minAlertLevel`, `--config`, `--glob`, `--filter` (an expression over rule fields); subcommands `sync`, `ls-config`, `ls-metrics`. Exit codes: 0 clean, 1 lint errors found, 2 runtime error.

Verified JSON shape (3.19.0): an object keyed by filename (`"stdin.md"` when piped) whose values are arrays of alerts with keys `Action{Name,Params}`, `Check` (`"write-good.So"`), `Description`, `Line`, `Link`, `Match`, `Message`, `Severity`, `Span` (`[startCol, endCol]`). `vale ls-metrics file.md` prints `{characters, complex_words, long_words, paragraphs, polysyllabic_words, sentences, syllables, words}`.

Short-snippet behaviour: a 48-word, 5-sentence paragraph run against all eight packages took **0.05 s wall-clock** and produced 26 alerts (AiTells 9, write-good 7, Microsoft 5, Google 2, proselint 1, alex 1, Readability 1). The Readability hit was a Flesch reading-ease warning computed on five sentences — readability formulas on snippets this short are noise, not signal (interpretation).

### 1e. proselint, write-good, alex, Joblint directly

| Tool | Runtime | Latest release | Repo activity | License | Notes |
|---|---|---|---|---|---|
| [proselint](https://github.com/amperser/proselint) | Python ≥ 3.10 | [PyPI 0.16.0, 2025-11-14](https://pypi.org/project/proselint/) (0.14.0 2024-05-23, 0.13.0 2021-11-07) | pushed 2026-08-26; 236 open issues; maintainers amperser, nytelife26 | BSD-3-Clause | `--output-format json`; 76 check modules |
| [write-good](https://github.com/btford/write-good) | Node | [npm 1.0.8, 2021-02-16](https://www.npmjs.com/package/write-good) | pushed 2025-03-10; 24 open issues, 0 PRs | MIT | `writeGood(text)` → `{index, offset, reason}`; checks passive, illusion, so, thereIs, weasel, adverb, tooWordy, cliches, eprime (off by default upstream; the Vale port ships it on at `suggestion`) |
| [alex](https://github.com/get-alex/alex) | Node ≥ 14, ESM-only (retext-equality + retext-profanities) | [npm 11.0.1, 2023-08-18](https://www.npmjs.com/package/alex) | pushed 2024-11-27 | MIT | |
| [Joblint](https://github.com/rowanmanning/joblint) | Node 0.10–5.x | npm 2.3.2, 2016-12-02 | **archived**; pushed 2023-03-13 | MIT | README: "very much not under active development and shouldn't really be used… I don't recommend using Joblint for anything serious" |

Only proselint is alive upstream. The Vale ports make the three runtimes moot for our purposes.

### 1f. Precedent for linting LLM output (secondary sources)

- **PostHog handbook**, [Vale and prose linting](https://posthog.com/handbook/docs-and-wizard/vale): LLMs "are not reliable linters… slow and expensive compared to deterministic tools"; "Use Vale to *detect* issues, then use LLMs to help *fix* them"; "Never send an LLM to do a linter's job."
- **ammil industries**, [Signs of AI writing: a Vale ruleset](https://ammil.industries/signs-of-ai-writing-a-vale-ruleset/) (Christian Miles, 2025-12-08): a Vale style derived from Wikipedia's "Signs of AI writing" page in three tiers (error: artifacts like "As an AI language model"; warning: em-dash overuse, hedging clusters; suggestion: "It's not just X, it's Y"). Repo [ammil-industries/vale-signs-of-ai-writing](https://github.com/ammil-industries/vale-signs-of-ai-writing), **CC-BY-SA-4.0**, 26 stars.
- **[krishnasunkam/vale-ai-tells](https://github.com/krishnasunkam/vale-ai-tells)** (MIT, created 2026-07-13): "A rule floor, not a detector" — names a specific mechanical tell and leaves the rewrite to you. Accepted into the official Vale registry as `AiTells` on 2026-08-25, so the Vale project itself now ships an AI-prose ruleset.
- **[tbhb/vale-ai-tells](https://github.com/tbhb/vale-ai-tells)** (MIT, created 2025-12-02, 82 stars, pushed 2026-08-31, v1.31.0): "Based on 2024-2025 research into vocabulary fingerprints and structural tells", aimed at technical documentation, plus a 15-rule commit-message style.
- No published example was found of piping proselint or write-good *directly* over model output as a gate; the pattern in the wild is Vale-based, and the packages above are the reusable pieces.

---

## 2. Deterministic legality checks for clues, in Elixir

### 2a. Stemmers and lemmatizers on hex.pm (registry API, 2026-09-01)

| Package | What | License | Latest | Signal |
|---|---|---|---|---|
| [`stemmer`](https://hex.pm/packages/stemmer) (fredwu) | Porter2 English, pure Elixir; `Stemmer.stem("capabilities") #=> "capabl"`, also sentences and lists | MIT | 1.2.0, 2024-01-14 (1.1.0 2022-01-09); 224k downloads | README: "100% compatible with the official Porter2 implementation, it is tested against the official `diffs.txt` which contains more than 29000 words" |
| [`text_stemmer`](https://hex.pm/packages/text_stemmer) (kipcole9) | 36 pre-compiled Snowball algorithms behind `Text.Stemmer.stem/2` (`:en`, `:en_porter`, `:en_lovins`…) | Apache-2.0 | 0.1.0, 2026-04-29 | README example: `stem_list(["running", "ran", "runs"], :en)` → `["run", "ran", "run"]` |
| [`snowball`](https://hex.pm/packages/snowball) (kipcole9) | Snowball compiler + runtime; `mix snowball.gen` turns `.sbl` into Elixir modules | Apache-2.0 | 0.1.1, 2026-05-10 | companion to `text_stemmer` |
| [`stemex`](https://hex.pm/packages/stemex) | NIF over C libstemmer, 17 languages | MIT | 0.2.1, 2023-10-09 | needs a C toolchain |
| [`stemmers`](https://hex.pm/packages/stemmers) | Rust NIF (rust-stemmers), precompiled | MIT | 0.1.0, 2026-07-16; 94 downloads | brand new |
| [`stem_ex`](https://hex.pm/packages/stem_ex) | original Porter | MIT | 0.0.2, 2017-01-05 | dormant |
| [`porter_stemming`](https://hex.pm/packages/porter_stemming) | Porter in Erlang | CC0-1.0 | 1.0.1, 2024-10-20 | |
| [`snowball_stemmer`](https://hex.pm/packages/snowball_stemmer), [`porter_stemmer`](https://hex.pm/packages/porter_stemmer) | Porter2 / Porter — **Gleam** packages | Apache-2.0 | 2.0.0 2026-05-31; 1.0.0 2024-10-20 | different toolchain |
| [`lemma`](https://hex.pm/packages/lemma) (xiamx) | FST-based morphological parser / lemmatizer; `Lemma.parse("plays")` → `{:ok, "play"}` | Apache-2.0 | 0.1.2, 2022-06-22 (repo pushed 2026-01-22) | README: "**Not for production use, this library is neither cpu nor memory efficient**" |
| [`inflex`](https://hex.pm/packages/inflex) | `Inflex.singularize/1`, `pluralize/1` (Rails-style inflections) | Apache 2.0 | 2.1.0, 2020-06-29; 38.7M downloads | plural handling only |
| [`exwordnet`](https://hex.pm/packages/exwordnet) | WordNet reader | MIT | 0.2.0, 2019-03-30 | dormant |

No maintained lemmatizer exists on hex; a lemma **lookup table** (2c) is the deterministic route.

### 2b. What Porter2 does and does not collapse

Looked up in Snowball's own English test vocabulary ([snowball-data/english `voc.txt` → `output.txt`](https://github.com/snowballstem/snowball-data), which `stemmer` reproduces exactly):

| Pair | Stems | Same? |
|---|---|---|
| dance / dancing / danced | `danc` / `danc` / `danc` | yes |
| dance / **dancer** | `danc` / `dancer` | **no** |
| run / running / **ran** / runner | `run` / `run` / `ran` / `runner` | inflection yes; irregular and agent noun no |
| happy / happiness / happily | `happi` / `happi` / `happili` | partly |
| nation / national / nationality | `nation` ×3 | yes |
| generous / generosity | `generous` / `generos` | no |
| sing / singer / song; child / children; mouse / mice; give / gave / given; colour / color | all distinct | no |

So stem-equality catches inflection and some derivation, and misses agent nouns, irregular forms, ablaut, and spelling variants — which is exactly what a "no shared root with the target" rule must catch (interpretation; see Signals).

### 2c. English wordlists, lemma tables, profanity lists — and their licenses

| Resource | What / size | License (verbatim where it matters) |
|---|---|---|
| **ENABLE** (`enable1.txt`, e.g. [dolph/dictionary](https://github.com/dolph/dictionary)) | 172,823 entries, verified **all lowercase `[a-z]`, 2–28 letters, no hyphens or apostrophes**; the Scrabble-oriented list ("the more verbose version of the *Official Scrabble Player's Dictionary*") | Public domain. SCOWL's [`scowl/Copyright` at rel-2020.12.07](https://github.com/en-wl/wordlist/blob/rel-2020.12.07/scowl/Copyright) preserves the ENABLE notice: "The ENABLE master word list, WORD.LST, is herewith formally released into the Public Domain… Please mention the source and credit us as originators of the list… you may *not* legally copyright or in any way restrict redistribution of the WORD.LST portion of your product." (The original host, wiki.puzzlers.org, did not resolve on 2026-09-01.) Membership nuance: `paris` and `french` are present (lowercase senses: plaster of paris, to french), `london`, `monday`, `jacob` are absent — membership means "has a lowercase dictionary sense", not "is never a proper noun". |
| **SCOWL classic** ([en-wl/wordlist tag rel-2020.12.07](https://github.com/en-wl/wordlist/tree/rel-2020.12.07); generator at [app.aspell.net/create](http://app.aspell.net/create)) | Sub-lists `<spelling>-<sub-category>.<size>`; sub-categories `abbreviations, contractions, proper-names, upper, words`; sizes 10…95. README: "The 'upper' category includes upper case words and proper names which are common enough to appear in a typical dictionary. The 'proper-names' category includes all the additional uppercase words. Finally the 'words' category contains all the normal English words." Size 80 "contains all the strange and unusual words people like to use in word games such as Scrabble" and includes ENABLE; 60 is recommended for spell checking | MIT-like: "Permission to use, copy, modify, distribute and sell these word lists… is hereby granted without fee, provided that the above copyright notice appears in all copies…" Sizes above 80 pull in UKACD, which carries its own restriction — the successor's Copyright says "If you are using a generated word list larger than 80, the copyright after '=== UKACD' applies." |
| **ESDB** (SCOWLv2, the repo's current form; release rel-2026.02.25 ships Hunspell/Aspell dictionaries) | one text file + SQLite DB with commonality, dialect variants, "(basic) part-of-speech, and inflection information"; minimum size 35, no 95 | [`Copyright`](https://github.com/en-wl/wordlist/blob/master/Copyright), 2000-2026: same MIT-like notice; "The primary source of words for ESDB comes from 12dicts and ENABLE2K. Both are in the Public Domain"; WordNet notice "MIGHT apply" if POS data is used |
| **AGID** 2016.01.19 ([`agid/README`](https://github.com/en-wl/wordlist/blob/rel-2020.12.07/agid/README); `infl.txt` 3.4 MB) | "an automatically created database of the inflected forms of words"; one line per word: `<word> <pos>: <inflected forms>` with `V`/`N`/`A` and variant markers | Kevin Atkinson's MIT-like notice; POS data carries the WordNet 1.6 notice. [wordlist.aspell.net/other](http://wordlist.aspell.net/other/): "AGID is no longer being mainatined" |
| **michmech/lemmatization-lists** | English: 41,760 tab-separated `lemma\ttoken` pairs (sourced from Hunspell dictionaries) | [ODbL-1.0](https://github.com/michmech/lemmatization-lists) (share-alike on the database); pushed 2022-01-29 |
| **Wiktionary via kaikki.org / wiktextract** | [kaikki.org English](https://kaikki.org/dictionary/English/index.html): "based on structured data extracted on 2026-08-28 from the enwiktionary dump dated 2026-08-05"; 1,385,953 distinct words; JSONL, 3.0 GB, with forms, POS, senses | Text is "dual-licensed… under both the Creative Commons Attribution-ShareAlike 4.0 International License (CC-BY-SA) and the GNU Free Documentation License (GFDL)" ([Wiktionary:Copyrights](https://en.wiktionary.org/wiki/Wiktionary:Copyrights)); wiktextract code MIT |
| **wordfreq** (Python) | word frequencies, 40+ languages; PyPI 3.1.1, 2023-11-21 | code Apache-2.0, "data files that may be redistributed under a Creative Commons Attribution-ShareAlike 4.0 license" ([README](https://github.com/rspeer/wordfreq)); frozen — [SUNSET.md](https://github.com/rspeer/wordfreq/blob/master/SUNSET.md): "the data is unlikely to be updated again" |
| **dwyl/english-words** | 466k+ words (`words_alpha.txt`, `words_dictionary.json`) | [Unlicense](https://github.com/dwyl/english-words), but the README says the list came from an infochimps spreadsheet and "Copyright still belongs to them"; no proper-noun filtering documented |
| **LDNOOBW** (Shutterstock's List of Dirty, Naughty, Obscene, and Otherwise Bad Words) | 28 language files; `en` has 403 lines | [CC-BY-4.0](https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words); pushed 2024-08-05; README: "what goes in these lists is subjective" |
| [`expletive`](https://hex.pm/packages/expletive) (Elixir) | `Expletive.configure(blacklist: …, whitelist: …)`, `profane?/2`, `profanities/2`, `sanitize/3`; ships `Expletive.Blacklist.english` (566 lines) and `international`; compiles a `\bword\b` regex with flags `iu`, `match_substrings: false` by default | Apache-2.0; 0.1.6, 2025-06-03; 280k downloads |

### 2d. How cjquines/just-one cancels duplicate clues

[cjquines/just-one](https://github.com/cjquines/just-one) (MIT; last push 2024-08-06; root deps `compromise ^13.11.4`, `express`, `socket.io`). The whole mechanism is one function in [`server/Room.js`](https://github.com/cjquines/just-one/blob/master/server/Room.js), lines 8–11:

```js
function equivalent(s1, s2) {
  if (!s1 || !s2) return false;
  return nlp(s1).text("root") === nlp(s2).text("root");
}
```

It is applied in `Room.startPhase("eliminate")` (same file, lines 315–343): in mode `"one"` a clue is hidden with `toggleClue(name)` when `playerOrder.filter(name_ => equivalent(clue, clues[name_].clue)).length > 1`; mode `"two"` hides unless exactly two match; mode `"schelling"` hides clues not `equivalent` to the modal clue. The same `equivalent(guess, this.word)` decides a correct guess in `handleGuess` (line 266).

What `"root"` means in compromise 13.11.4: `Term.setRoot` ([`src/Term/methods/03-misc.js`](https://github.com/spencermountain/compromise/blob/13.11.4/src/Term/methods/03-misc.js)) starts from the cleaned lowercase term, applies `transform.toSingular` when the term is tagged `Plural`, and `transform.toInfinitive` (by detected tense: PastTense, Gerund, PresentTense, Participle, Actor) when tagged `Verb` and neither `Negative` nor `Infinitive`; `doc.text('root')` ([`src/Doc/methods/output/01-text.js`](https://github.com/spencermountain/compromise/blob/13.11.4/src/Doc/methods/output/01-text.js)) caches roots for every term and joins them. So it is tag-and-lexicon lemmatization (singular nouns, infinitive verbs), not Porter stemming. Nothing in the repo checks a clue against the mystery word's family, proper nouns, or multi-word clues — those rules are left to the humans at the table.

---

## 3. Schema guarantees across providers (brief)

**Anthropic** — [Structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs) (GA, no beta header; `output_format` is the deprecated spelling): two features, "JSON outputs (`output_config.format`)" with `type: "json_schema"`, and "Strict tool use (`strict: true`): Guarantee schema validation on tool names and inputs" ([strict tool use](https://platform.claude.com/docs/en/agents-and-tools/tool-use/strict-tool-use): "Tool `input` strictly follows the `input_schema`"; "Tool `name` is always valid"). The promise: "Structured outputs guarantee schema-compliant responses through constrained decoding: Always valid: No more `JSON.parse()` errors… Type safe: Guaranteed field types and required fields". Documented exceptions ("Invalid outputs"): `stop_reason: "refusal"` (HTTP 200, "The output may not match your schema because the refusal message takes precedence"), `stop_reason: "max_tokens"` ("The output may be incomplete"), and enum casing ("Structured outputs don't guarantee the capitalization of string `enum` and `const` values… Compare enum values case-insensitively"). Schema subset: no recursive schemas, no `minimum`/`maximum`/`multipleOf`, no `minLength`/`maxLength`, `minItems` only 0 or 1, `additionalProperties` must be `false`, `pattern` supported without `\b` or lookarounds; limits of 20 strict tools, 24 optional parameters and 16 union-typed parameters per request, else 400. Grammars compile on first use and are "cached for 24 hours from last use"; an extra system prompt is injected ("costs you tokens"); incompatible with citations and prefill; works with batches and streaming; "Grammars apply only to Claude's direct output, not to… thinking tags". SDKs: `client.messages.parse()` validates and returns `parsed_output`.

**OpenAI** — [Structured model outputs](https://developers.openai.com/api/docs/guides/structured-outputs): enabled with `text: { format: { type: "json_schema", "strict": true, "schema": … } }` (Responses API); "ensures the model will always generate responses that adhere to your supplied JSON Schema, so you don't need to worry about the model omitting a required key, or hallucinating an invalid enum value." Edge cases are named: "the model might not generate a valid response that matches the provided JSON schema. This can happen in the case of a refusal… or if for example you reach a max tokens limit and the response is incomplete" (refusals arrive in a separate `refusal` field). Subset: all fields must be `required` (emulate optional with `null` unions), `additionalProperties: false` required, root must be an object (not `anyOf`), up to 5,000 properties and 10 nesting levels, 120,000 chars of names/enum/const strings, 1,000 enum values; supported keywords include string `pattern`/`format`, number `minimum`/`maximum`/`multipleOf`, array `minItems`/`maxItems`, `$defs` and **recursive schemas**; unsupported: `allOf`, `not`, `if/then/else`. "outputs will be produced in the same order as the ordering of keys in the schema"; the first request with a schema has "additional latency as our API processes the schema". Plain JSON mode (`type: "json_object"`) "will not guarantee the output matches any specific schema, only that it is valid and parses". Honest footnote: "Structured Outputs can still contain mistakes."

**Google Gemini** — two API surfaces. The current [Structured outputs guide](https://ai.google.dev/gemini-api/docs/structured-output) (last updated 2026-08-26) targets `POST …/v1beta/interactions` with `response_format: { "type": "text", "mime_type": "application/json", "schema": {…} }`: "You can configure Gemini models to generate responses that adhere to a provided JSON Schema"; supported `string, number, integer, boolean, object, array, null` with `title, description, properties, required, enum, format, minimum, maximum, items, prefixItems, minItems, maxItems, additionalProperties`, plus `anyOf` and `$ref` recursion; "Not all JSON Schema features are supported", "Very large or deeply nested schemas may be rejected", streamed chunks "are valid partial JSON strings"; and the explicit caveat "While output is syntactically correct JSON, always validate values in your application." The classic `generateContent` API ([v1beta discovery document](https://generativelanguage.googleapis.com/$discovery/rest?version=v1beta), revision 20260831) exposes `GenerationConfig.responseMimeType` (`application/json`, `text/x.enum`), `responseSchema` — "Schemas must be a subset of the OpenAPI schema" — now flagged `"deprecated": true`, and `responseJsonSchema`, which accepts JSON Schema with only `$id $defs $ref $anchor type format title description enum items prefixItems minItems maxItems minimum maximum anyOf oneOf properties additionalProperties required` (+ non-standard `propertyOrdering`; "Cyclic references are unrolled to a limited degree"). Truncation and safety stops are signalled by `finishReason` (`MAX_TOKENS`, `SAFETY`, `RECITATION`, `BLOCKLIST`, `PROHIBITED_CONTENT`), with no statement that a truncated response parses. (Quirk for the record: in the discovery document the field named `responseJsonSchema` carries a placeholder description and the keyword list sits on a deprecated `_responseJsonSchema` twin.)

Net: all three constrain decoding to the schema, none guarantees the *values*, all three carve out refusals and token exhaustion, and Anthropic and Gemini support fewer numeric/string constraints than OpenAI — so a deterministic validator on our side is still the last word.

---

## Signals for our design (inference)

Everything below is our interpretation of the sources above, not a claim they make.

### Guardrail pipeline per role

**Author (pre-play, offline — latency is free, so be strict)**
1. Ask for the Page as JSON via `output_config.format` (or one strict tool). Keep grades and categories as string enums; the schema cannot carry `minimum`/`maximum`, so ranges are clamped in Elixir.
2. Check `stop_reason` first (`refusal` / `max_tokens` → discard and retry), then validate with [`jsv`](https://hex.pm/packages/jsv) (0.22.0, 2026-08-07, Apache-2.0, current JSON Schema drafts; `ex_json_schema` 0.11.5 is draft-4 only, `json_xema` 0.6.5 covers 4/6/7).
3. Legality filter, pure Elixir, on every target word, decoy and pre-written clue:
   - *one word*: NFC-normalize, downcase, trim; `~r/^[a-z]+$/` (make the hyphen policy explicit rather than accidental).
   - *is a word*: membership in an ENABLE `MapSet` loaded from `priv/` at boot (or a SCOWL list built with `mk-list` at size ≤ 80 — never above, to avoid UKACD terms).
   - *not a proper noun*: ENABLE is lowercase-only, so anything that only exists capitalized fails membership. For the `paris` case, also build SCOWL's `proper-names` and `upper` sub-lists: reject when the capitalized form is there and the lowercase form is not in `words`; flag as ambiguous when both exist and let the Author's own `is_proper_noun` field or a human decide.
   - *no shared root with the target*: reject if `Stemmer.stem(clue) == Stemmer.stem(target)`, **or** either stem is a prefix of the other word (catches `danc` in `dancer`, `sing` in `singer`), **or** the two appear in the same AGID inflection line (catches `ran`, `children`, `mice`), **or** they share a lemma in the michmech table. Porter2 alone is not enough (2b).
   - *no profanity*: `Expletive.profane?/2` with `Expletive.Blacklist.english` merged with LDNOOBW `en`, whole-word matching (the default), plus a whitelist for false positives.
   - *novelty*: not used as a target in the last N Pages of the Chronicle (exact and stem match).
4. On rejection, regenerate with the machine-readable reasons appended (deterministic rejection, model repair), bounded to a few rounds; then rank the survivors (design law 4).

**Meter (live, at the reveal)**
- Deterministic pre-checks before any call: identical normalized strings → top grade; same Porter2 stem → one below top; blocklisted → refuse. Consult the Author's pre-graded pairs first (law 13) so the live call is the exception.
- Tiny strict schema: `{grade: enum, reasoning: string}`. Validate with `jsv`; compare enums case-insensitively (Anthropic's documented casing caveat); treat `refusal`/`max_tokens` as "no verdict" and fall into the provisional-result path of law 10.
- Verdict-cache key = `{model, prompt_version, schema_hash, normalize(a), normalize(b)}` with `normalize` = NFC + downcase + trim + collapse whitespace and nothing cleverer — a stemmed key would make "dancer" and "dancing" share one cached ruling, which is a visible self-contradiction waiting to happen (law 1).
- Grade both orderings (law 12) and merge with a fixed deterministic rule (e.g. the lower grade wins; disagreement is recorded in the reasoning shown to the couple).

**Scribe (post-play)**
- Write the draft to a temp file and run `System.cmd("vale", ["--config=priv/vale/scribe.ini", "--output=JSON", "--no-exit", path])` — [`System.cmd/3`](https://elixir.hexdocs.pm/System.html) has no stdin option (it "uses a `Port`" internally), so file input is simpler than `--ext=.md` piping. Decode the JSON; `error` blocks, `warning`/`suggestion` are logged.
- `scribe.ini`: `BasedOnStyles = Vale, Scribe, write-good, proselint, AiTells`; `Vocab = Chronicle` with `accept.txt` (Melissa, Jacob, Page, Chapter, Chronicle, Give, Meter — enforces exact casing) and `reject.txt` (delve, tapestry, testament, …). Leave alex, Joblint, Microsoft and Google off — they are tech-docs and job-ad styles and will fight a narrative voice — and keep Readability at `suggestion` or off (1d). Add a `metric` rule for length and an `existence` rule for em dashes only if that is genuinely the house voice.
- Deterministic structure checks in Elixir: the Page record itself (date, Page id, rulings, overrules) is JSON validated with `jsv`; word budget from `vale ls-metrics` or `String.split/1`.
- Repair loop: at most one model rewrite with the alert list attached (the PostHog pattern: linter detects, model fixes). If errors persist, keep the draft with the fewest errors, log them, and write it anyway — the Chronicle is player-editable by law 5, and a missing Page is worse than a purple one.
- Determinism of the gate itself: pin package zips by release URL in `Packages = …` (the `Packages` key accepts URLs) and vendor the synced `styles/` directory into the deploy, since `vale sync` needs the network and "latest" drifts.

### Shell out vs implement in Elixir

| Job | Where | Why |
|---|---|---|
| Prose lint | Shell out to the Vale binary (`vale_3.19.0_Linux_64-bit.tar.gz` on stephens.page's Ubuntu 24.04; macOS arm64 locally) | one Go binary covers proselint / write-good / alex / Joblint / Microsoft / Google / AiTells; 0.05 s per snippet; JSON out |
| proselint, write-good, alex natively | Do not | would add Python and Node runtimes for subsets Vale already ports; upstream write-good, alex and Joblint are dormant or archived |
| Stemming | Elixir `stemmer` (Porter2, pure Elixir, exact Snowball parity); `text_stemmer` if other languages ever matter | no NIF, no toolchain |
| Lemma / inflection family | Elixir map built at boot from AGID `infl.txt` (and optionally michmech `en`) | deterministic, fast, licensable; `lemma` on hex is explicitly not production-grade, `inflex` only does number |
| Wordlists | Elixir `MapSet`/ETS from files in `priv/` | ENABLE is 172k lowercase lines; trivial |
| Profanity | Elixir `expletive` + LDNOOBW list | word-boundary matching built in |
| JSON Schema validation | Elixir `jsv` | belt-and-braces on top of provider constrained decoding |

### License cautions

- **ENABLE**: public domain, but the notice asks "Please mention the source and credit us" — add a line to a NOTICE file.
- **SCOWL / ESDB**: MIT-like; keep Kevin Atkinson's notice; stay at size ≤ 80 (UKACD terms apply above). **AGID**: same notice; using its POS field drags in the WordNet 1.6 notice.
- **michmech lemma lists**: ODbL is share-alike *on the database* — fine for a household toy, but a public release that redistributes a derived table must ship it under ODbL. Prefer AGID for anything public.
- **Wiktionary / kaikki** and **wordfreq data**: CC BY-SA 4.0 (Wiktionary also GFDL) — share-alike, and kaikki is 3 GB. Only worth it if we need senses; wordfreq is frozen at 2021 data anyway.
- **dwyl/english-words**: "Unlicense" over a list whose upstream copyright the README itself concedes — avoid.
- **LDNOOBW**: CC BY 4.0 — attribution in NOTICE. **expletive**: Apache-2.0, list included.
- **Vale** MIT; **proselint port** BSD-3-Clause, other ports MIT; **AiTells** and **tbhb/vale-ai-tells** MIT; the **ammil** ruleset is CC BY-SA 4.0 — copying its rules into our `Scribe` style would make that style share-alike, so borrow ideas, not YAML.
- Provider structured-output docs carry no license implications; Anthropic's only content rule (no PHI in schemas) does not apply.

### What a deterministic wrapper cannot do

Decide whether "paris" is the city tonight, whether "bakery" is too close to "baker", or whether a graded verdict is *fair*. Those are judgment calls, and the design already has the right answer for them: the couple's joint overrule, recorded in the Chronicle as precedent (law 3). The wrappers above exist so that the machine never wastes that authority on a malformed page, an illegal clue, or a paragraph that says "delve".
