# Demo org load scripts — Intro to Claude and Salesforce

Anonymous Apex to build the demo environment for the DUG session *Intro to
Claude and Salesforce* — the Acme Manufacturing story and the filler records
the live demo segments query against.

Run these in **Developer Console → Debug → Open Execute Anonymous Window**, with
*Open Log* checked so you can read the `USER_DEBUG` output.

## Run order

| # | Script | When |
|---|---|---|
| 1 | `apex/01_load_demo_data.apex` | Now, and again before Wednesday's run-through. Re-runnable. |
| 2 | `apex/02_verify_demo.apex` | Right after the loader, as a **separate** execution. |
| — | `apex/00_cleanup.apex` | After the talk, or any time you want the org empty. |

The two-step split is not stylistic: `LastActivityDate` is a platform rollup
computed after the loading transaction commits, so querying it in the same
execution returns `null`. Verification has to be its own run.

The loader wipes and rebuilds, so running it twice is safe — nothing
accumulates. That is what makes it usable for Wednesday's timed run-through.

## What it creates

**Acme Manufacturing** — the story from slide 21:

- $250K annual platform renewal, `Negotiation/Review`, closing two days before
  quarter end, owned by you
- Last completed activity 23 days ago, so "quiet for three weeks" is literally true
- Escalated high-priority case: conveyor controller firmware defect halting Line 3
- Dana Whitfield, **VP of Operations** — the new hire the slide 22 "Act" prompt
  emails. Her description spells out that she joined three weeks ago and has
  never been contacted.
- Plus Marcus Reyes (Director of IT, opened the case) and Priya Raman (Procurement)

**18 filler accounts**, each with a contact, an opportunity and two completed
activities. Amounts run $39K–$310K across six open stages, with last-activity dates
deliberately spread from 1 to 33 days ago. Two closed deals (one won, one lost)
so pipeline-by-stage isn't all open pipeline.

The activity spread is tuned so the first demo prompt lands well. No stale deal
anywhere in the set is larger than Acme's $250K, so Acme tops the "quiet deals
by amount" list no matter how ownership shakes out — including in a one-user org
where every filler deal falls to you. Meanwhile Northgate's $310K sits *above*
Acme in the unfiltered pipeline with activity 3 days ago, so the 14-day filter
visibly does work rather than just surfacing the biggest deal in the org.

If you edit the amounts, keep that invariant: nothing stale above $250K.
`02_verify_demo.apex` fails loudly if you break it.

## Slide-by-slide coverage

| Slide | Prompt | Backed by |
|---|---|---|
| 22 (1) | "Which of my opportunities closing this quarter have had no activity in the last 14 days? Sort by amount." | Stale-vs-fresh activity spread; Acme tops the list |
| 22 (2) | "Give me a full briefing on Acme Manufacturing…" | Opportunity + case + contacts + activity history on one account |
| 22 (3) | "Draft a follow-up email to the new VP of Operations…" | Dana Whitfield, plus a writable org for the task Claude creates |
| 22 (4) | "…build an interactive dashboard: pipeline by stage, deals at risk, filter by owner" | Six stages, up to four owners, 19 open deals this quarter |
| 3 | "Brief me on Acme Manufacturing before my 2pm call" | Same data as 22 (2) |

## Before you run

- **Developer Edition org or a sandbox.** The loader asserts on this and
  refuses to run anywhere else — matching "Never use a real client org on
  screen." If you genuinely need to override it, delete the assert block at the
  top.
- **Create 2–3 extra active users first** if you want the dashboard's "filter by
  owner" to mean anything. A fresh Developer Edition org has one user, so every
  deal would be yours. The loader warns you in the debug log if it finds only
  one, and otherwise spreads ownership across up to four users with you holding
  Acme and most of the at-risk deals.
- Your user needs create access on Account, Contact, Opportunity, Case and Task.

## Assumptions, and where they might not hold

These are written against a stock org. Each one degrades gracefully rather than
erroring, but check the debug log if something looks off.

- **Picklists.** Stage, industry, opportunity type, case status/type, task status
  and account type are all validated against your org's actual picklist values
  before use, falling back to a safe value or `null`. If your org renamed
  `Negotiation/Review`, Acme will land on `Prospecting` instead — fix it in the
  script or by hand.
- **Fiscal year.** Close dates are placed in the current **calendar** quarter.
  SOQL's `THIS_QUARTER` follows your org's *fiscal* calendar, so if you've
  configured a custom fiscal year the demo query may not match. `02_verify_demo`
  catches this and says so.
- **Required custom fields.** If someone has added a required custom field to any
  of these objects, the insert fails. The error will name the field.
- **Validation rules and triggers.** Same — a validation rule on Opportunity
  could reject these records. Turn it off or adjust the data.
- **Case age can't be faked.** Apex can't backdate `CreatedDate` outside of a
  test context, so the escalated case shows as created today. The 12-day age is
  written into the subject and description instead, which is what Claude reads
  anyway. If you want a genuinely aged case on screen, create it by hand now and
  leave it alone until Thursday.

## Still to do from the Demo Environment section

The scripts cover the org. These are separate and not automatable from here:

- **Cowork "Acme" folder** with 2–3 realistic meeting notes files — needed for
  the slide 10 handoff and the slide 23 reveal, and specifically for the "it
  combined Salesforce data *and* local meeting notes" point. Worth writing notes
  that reference Dana Whitfield's arrival and the Line 3 defect so the QBR deck
  visibly ties them together.
- **Limited-access test user** for the optional security demo ("Claude only sees
  what you can see").
- **Hosted MCP connector** setup and the screenshots for slides 16–18.
