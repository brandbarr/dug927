# Demo org load scripts — Intro to Claude and Salesforce

Anonymous Apex to build the demo environment for the DUG session *Intro to
Claude and Salesforce* — the Acme Manufacturing story plus enough surrounding
data that the org reads like a real one rather than a fixture.

**2,778 records across 11 objects.**

There are two ways to run them. Either drive the whole thing from the repo root
with [go-task](https://taskfile.dev) and the Salesforce CLI:

```
task doctor ORG=my-dev-org     # check the CLI, the org, and its user licences
task setup  ORG=my-dev-org     # load everything and verify it
```

`task setup` runs the four loaders in order and then the verifier, refusing to
start unless the target org is a Developer Edition org or a sandbox. It is
re-runnable — nothing accumulates. `task --list` shows the rest (`verify`,
`smoke`, `clean`, `reload`, `open:acme`). The Taskfile needs go-task 3.28+ and
`sf` v2, and targets an org you have already authenticated by alias.

Or paste each script by hand into **Developer Console → Debug → Open Execute
Anonymous Window**, with *Open Log* checked so you can read the `USER_DEBUG`
output. Same scripts, same order.

## Run order

Order matters. Scripts 02–04 look up records that 01 creates.

| # | Script | Creates | Records |
|---|---|---|---|
| 1 | `apex/01_load_core.apex` | Accounts, contacts, opportunities, tasks, events | 1,577 |
| 2 | `apex/02_load_service.apex` | Cases, case comments | 98 |
| 3 | `apex/03_load_marketing.apex` | Campaigns, leads, campaign members | 363 |
| 4 | `apex/04_load_products.apex` | Products, price book entries, line items | 740 |
| 5 | `apex/05_verify_demo.apex` | Nothing — runs the demo's queries and reports PASS/FAIL | — |
| — | `apex/00_cleanup.apex` | Nothing — removes all of the above | — |

**Re-running 01 means re-running 02, 03 and 04 behind it.** Script 01 wipes and
rebuilds the accounts, which cascade-deletes the cases and line items that 02
and 04 created. Each script cleans up its own scope first, so running any of
them twice is safe and nothing accumulates — that is what makes this usable for
Wednesday's timed run-through.

Verification has to be its own execution. `LastActivityDate` is a platform
rollup computed after the loading transaction commits, so querying it inside
that transaction returns `null` and every staleness check would fail.

Data is generated from a fixed seed, so every run produces identical records.
You can rehearse against the org and trust what you saw.

## What it creates

**Acme Manufacturing** — the story the live demo runs on:

- **$250K annual platform renewal**, `Negotiation/Review`, closing two days
  before quarter end, owned by you. Last activity 23 days ago, so "quiet for
  three weeks" is literally true rather than merely asserted.
- **Five contacts**, including Dana Whitfield (VP of Operations, joined three
  weeks ago, never contacted — the target of the slide 22 "Act" prompt), Marcus
  Reyes (Director of IT, the champion who went quiet), Alan Voss (Plant Manager
  at the affected site) and Teresa Nunez (CFO, has asked twice about the outages)
- **Four cases with five comments**: the escalated Line 3 firmware defect the
  demo hinges on, a closed first occurrence of the same bug, a billing question
  and an open feature request. The comments carry the day-by-day back-and-forth,
  including an internal note tying the defect to the unbriefed VP.
- **A second open opportunity** ($40K Line 4 sensors) explicitly blocked on
  fixing Line 3, plus three closed deals going back two years

**249 filler accounts** across 23 industries, each with one or two contacts.
Every account name is a unique prefix/suffix pairing, so nothing repeats.

- **360 opportunities**: 161 open (104 closing this quarter, the rest later),
  199 closed across two years of history at a ~64% win rate
- **571 activities**: completed tasks driving `LastActivityDate`, plus events
  for meetings. Recency is spread 0–44 days so "no activity in 14 days" divides
  the pipeline rather than returning everything or nothing.
- **93 cases**, so Acme is not the only account with a support footprint
- **150 leads** and **6 campaigns** with 206 members, covering both leads and
  contacts so "which campaigns touched this account?" has an answer
- **720 opportunity line items** drawn from 10 products

## The one invariant

No stale deal anywhere may be worth more than Acme's $250K, or Acme stops
topping the slide 22 *"quiet deals closing this quarter, sorted by amount"*
query and the demo's first beat lands wrong.

Script 01 enforces it: any deal that would close this quarter, be stale, and
exceed $250K gets clamped into the $180K–$239K band. Clamped to a *range*, not
a single value — half a dozen deals showing an identical amount looks synthetic
on a projector, which is the one place this data gets scrutinised.

Meanwhile a $312K deal with three-day-old activity sits **above** Acme in the
unfiltered pipeline, so the 14-day filter visibly does work rather than just
surfacing the biggest deal in the org.

`05_verify_demo.apex` checks both halves of that and fails loudly if either
breaks. If you edit the amount tiers, re-run it.

## Slide-by-slide coverage

| Slide | Prompt | Backed by |
|---|---|---|
| 22 (1) | "Which of my opportunities closing this quarter have had no activity in the last 14 days? Sort by amount." | 104 open deals this quarter, ~78 of them stale, Acme on top |
| 22 (2) | "Give me a full briefing on Acme Manufacturing…" | 5 contacts, 5 opportunities, 4 cases, 5 case comments, 6 activities on one account |
| 22 (3) | "Draft a follow-up email to the new VP of Operations…" | Dana Whitfield, plus a writable org for the task Claude creates |
| 22 (4) | "…build an interactive dashboard: pipeline by stage, deals at risk, filter by owner" | 6 stages, up to 6 owners, 104 open deals |
| 24 | "Your turn" — whatever the room asks | Leads, campaigns, products and two years of closed history give unscripted questions somewhere to land |
| 3 | "Brief me on Acme Manufacturing before my 2pm call" | Same data as 22 (2) |

Two years of won/lost history at a stable win rate also sets up the DRiV
forecasting tie-in at 3:15, if you want to gesture at it.

## Before you run

- **Developer Edition org or a sandbox.** Every script asserts on this and
  refuses to run anywhere else, matching "Never use a real client org on
  screen." To override, delete the assert block at the top.
- **Add another user if you can.** With one user, all 250 accounts are yours and
  the dashboard's "filter by owner" is a no-op. Script 01 spreads ownership
  across up to six users, keeping Acme and a large share of the at-risk deals
  with you, and warns in the debug log if it finds only one.

  The constraint: a **Developer Edition org ships with 2 Salesforce licences**,
  so you can add exactly one more opportunity owner there — two groups, which is
  enough for the filter to do something visible. Platform licences cannot own
  opportunities, so they do not help. For real owner variety you need a sandbox
  of a fuller org. `task doctor` prints your licence counts.
- Your user needs create access on Account, Contact, Opportunity, Task, Event,
  Case, Lead, Campaign, Product2 and OpportunityLineItem.

## Assumptions, and where they might not hold

Written against a stock org. Most of these degrade gracefully rather than
erroring, but read the debug log if something looks off.

- **Picklists** are validated against your org's real values before use —
  stages, industries, opportunity and account types, case status/type/origin/
  reason, task status, lead status and source, campaign type — falling back to a
  safe value or `null`. If your org renamed `Negotiation/Review`, Acme lands on
  the first available open stage instead.
- **Fiscal year.** Close dates are placed in the current **calendar** quarter,
  but SOQL's `THIS_QUARTER` follows your org's *fiscal* calendar. With a custom
  fiscal year the two disagree; check 2 in the verify script catches it.
- **Products override amounts.** This is the sharp edge. Once an opportunity has
  line items, Salesforce recomputes `Amount` as their sum, which would destroy
  the amount spread — including Acme's exact $250K. Script 04 therefore gives
  each deal two line items that sum to its existing amount to the dollar, and
  both it and check 7 verify nothing drifted. If check 7 ever fails, delete the
  demo line items and skip script 04; everything else works without it.
- **Multi-currency orgs** need `CurrencyIsoCode` on price book entries, which
  script 04 does not set. If your org has multiple currencies enabled, skip 04.
- **Required custom fields, validation rules and triggers** on any of these
  objects will reject the inserts. The error names the field or rule.
- **Case age cannot be faked.** Apex cannot backdate `CreatedDate` outside a
  test context, so cases show as created today. The 12-day age of the Acme
  defect lives in its subject, description and comments instead, which is what
  Claude actually reads. For a genuinely aged case on screen, create that one by
  hand a few days early and leave it alone.
- **Governor limits** are not close: the largest transaction is script 01 at
  1,577 DML rows against a 10,000 cap, and 04 at 1,100. Pushing filler accounts
  past roughly 1,500 would need chunked runs or Batch Apex.

## Still to do, outside these scripts

- **Cowork "Acme" folder** with 2–3 meeting notes files — needed for the slide 10
  handoff and the slide 23 reveal, and specifically for the "it combined
  Salesforce data *and* local meeting notes" point. Worth writing notes that
  reference Dana Whitfield's arrival and the Line 3 defect so the QBR deck
  visibly stitches the two sources together.
- **Limited-access test user** for the optional security demo ("Claude only sees
  what you can see").
- **Hosted MCP connector** setup and the screenshots for slides 16–18.
