# AnkEdo Agent

Hate-speech monitoring for Arabic and Kurdish social media targeting Iraqi minorities —
Yazidis, Christians and Assyrians, Shabak, Kaka'i, Sabian-Mandaeans, Turkmen, Faili
Kurds, Baháʼís, Kurds.

An [OpenClaw](https://github.com/openclaw/openclaw) plugin. OpenClaw supplies the agent
loop, model providers, scheduling and the control UI; this supplies the judgement.

## What it does

It collects, judges, keeps its own record, and puts findings in front of a human.

**It judges in context.** `اعوذ بالله من الشيطان الرجيم` is an ordinary pious phrase.
Under a post about a Yazidi ceremony at Lalish it invokes the devil-worship libel. The
same words are a different act in a different place, so a comment is always judged
against what it replies to.

**It refuses to fire on words alone.** `نجس` about drinking water is a complaint about
water. `الخونة` in an argument about the government is ordinary Iraqi political speech.
A trope only fires when its activation condition is met.

**It does not flag the people defending the community.** Counter-speech reproduces the
exact words it condemns — and the person quoting a libel is usually the person
rejecting it. Flagging them is the specific harm this project can cause, so
`never_flag_when` and negation cues are enforced in code.

**It learns when and where to look, and says what it is missing.** Crawl windows come
from an hour-of-day histogram of when flagged content was *posted*. A fifth of crawls
deliberately go outside those windows, because otherwise the record describes the
crawler's habits rather than reality — and `case_status` reports that gap rather than
hiding it.

## Tools

| Tool | What it answers |
|---|---|
| `classify` | Is this hate speech, given what it replies to? |
| `lexicon_status` | What am I matching with, and how old is it? |
| `case_open` | Start a monitoring campaign |
| `case_status` | State, findings, learned hours, coverage gaps |
| `review_queue` | What is waiting for a human? |
| `next_crawl` | Should I be running right now, and where? |

## The lexicon is not in this repository

It belongs to the Ettok platform. A curator adds a term in the dashboard and the agent
picks it up on the next sync. Nothing here hardcodes a term, and the agent may only
*propose* additions through `lexicon-gaps/` — it contributes without the authority to
rewrite its own rules.

Verdicts record how stale the dictionary was when they were made. Recall degrades
silently against an old lexicon, and a reviewer reading a report months later needs to
know what judged it.

## Install

Requires **Node ≥22.22.3, ≥24.15, or ≥25.9**.

```bash
npm install -g openclaw

git clone https://github.com/amirjundi/ankedo-agent.git
cd ankedo-agent
npm install
npm run build

openclaw config set plugins.load.paths '["'"$PWD"'"]'
openclaw plugins enable ankedo
```

Then point it at the platform:

```bash
openclaw config set plugins.entries.ankedo.config.platformUrl https://ettok.net/api/hermes/
openclaw config set plugins.entries.ankedo.config.agentKey <key with the hate_speech_scan scope>
openclaw config set plugins.entries.ankedo.config.agentId ankedo-<hostname>
openclaw config set plugins.entries.ankedo.config.databasePath ~/.ankedo/evidence.db
```

`agentId` is not optional in practice: the platform scopes idempotency on
`(agent_id, key)`, so two machines omitting it share a namespace and one silently
replays the other's response.

### Collection

Collection uses [Camoufox](https://camoufox.com), a hardened Firefox fork — not
OpenClaw's bundled browser, which drives Chromium over CDP with no anti-detection. CDP
is exactly what social platforms fingerprint, and a fingerprinted worker account is a
banned one.

```bash
npm install camoufox
npx camoufox fetch

openclaw config set plugins.entries.browser.enabled false
```

Everything except collection works without a browser. If Camoufox will not start, the
agent classifies as normal and says so plainly rather than failing to start.

## The persona

`workspace/SOUL.md` and `workspace/AGENTS.md` are what make this a monitor rather than
a general assistant. Copy them into the agent workspace:

```bash
cp workspace/*.md ~/.openclaw/workspace/
```

`AGENTS.md` carries the standing orders — which actions run unattended and which wait
for a human. Reactivating a dormant case, changing a threshold and submitting verdicts
all wait.

## Tests

```bash
npm test          # 123 unit tests
npm run test:e2e  # 9 end-to-end, against a stub platform over real HTTP
```

The normaliser is checked against fixtures generated from the platform's own canonical
fold, so the two cannot drift apart silently. That guard matters: if the folding
diverges, matching quietly stops working for terms containing yeh or alef maksura and
nothing errors.

## Licence

MIT, and built on OpenClaw (MIT, © 2026 OpenClaw Foundation).
