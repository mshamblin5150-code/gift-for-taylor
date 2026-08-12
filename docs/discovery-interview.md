# Discovery Interview — Taylor (ED Manager)

A working document. Read it before, use it during, fill it in after.

**Goal:** find the one problem worth building for — including the one she's stopped noticing.

**Context:** Taylor manages the emergency department and is my direct manager. She's also a working nurse — she carries clinical load on top of the management job. This is for a servant-leadership assignment, and the intent is to actually ship her something.

---

## Hard constraint: no patient data. None.

Read this before anything else, because it decides which problems are even eligible.

**Whatever gets built must be structurally incapable of holding protected health information.** Not "we'll be careful" — incapable. No names, no MRNs, no dates of birth, no room numbers tied to people, no chief complaints, no free-text field where someone could paste a handoff note.

This isn't hypothetical caution. A tool that touches PHI without the hospital's compliance and IT sign-off is a HIPAA exposure for her and a fireable one for you, and building it as a *gift* makes it worse, not better — it arrives outside every channel that would normally vet it.

### What that rules out

- Anything touching the EHR (Epic, Cerner, Meditech) — reading from it, scraping it, storing exports from it
- Anything living on the hospital network, or needing hospital SSO, or installed on a hospital-managed machine
- Patient tracking, boarding lists, handoff tools, anything with a patient in it at all
- Photos of the tracking board. Photos of anything.

### What that leaves — and it's a lot

The administrative and people-management half of her job, which is where managers actually drown:

- **Staff**, not patients — schedules, callouts, coverage, certifications, onboarding
- **Aggregate numbers** with no individual behind them — monthly volume, door-to-doc averages, LWBS rate
- **Things**, not people — equipment, supplies, checklists, logs
- **Her own workflow** — her task list, her follow-ups, her recurring reports

### One more line, on aggregate data

Even de-identified departmental metrics can be internally sensitive — LWBS rates and throughput numbers are not things hospitals like seeing outside their walls. Rule of thumb: if it would live anywhere other than her own device, ask her whether it's OK to leave the building. She'll know. Asking also signals you take this seriously, which matters given who she is to you.

**If the best problem you find turns out to require PHI: don't build it. Pick the runner-up.** Write down the PHI-blocked one in your assignment notes — recognizing the constraint and choosing the servable problem instead is a stronger finding than building the wrong thing.

---

## The one rule

**Do not tell her you're building something.**

The moment she knows, she stops reporting and starts helping. She'll suggest features, soften complaints, and manage your expectations — she's a manager, that's reflex. Every answer after that point is contaminated and you won't be able to tell which ones.

You don't need a cover story, because the true one is better than any lie:

> *"I have a servant-leadership assignment for school. Can I get 30 minutes to ask you about how your job actually goes?"*

That's completely honest, it's a normal thing for staff to ask a manager, and most managers are pleased to be asked. It reveals nothing about the build.

## Before you go: write down what she's already told you

She vents downward. That means you've been collecting data for months without calling it that — and it's better data than the interview will produce, because it wasn't performed for you.

**Sit down for ten minutes and list every complaint you've heard her make.** Do it before the conversation, not after. Two reasons: it stops you from "discovering" things you already knew and calling it insight, and the gaps between your list and what she says in the interview are themselves interesting.

```
Things I've already heard Taylor complain about:




The idea I walked in wanting to build:


```

That second box is the guard against building what you already decided to build. Fill it in honestly and don't look at it again until scoring.

## Running it on Taylor

She's your manager *and* a working nurse *and* someone who vents to you. Each changes the posture.

**Because she vents downward:**

- **Your risk isn't silence — it's volume.** Guarded managers give you too little; venting ones give you too much of the *loudest* thing. A vent is an emotional peak, and peaks are rare by definition. The catastrophic night she still talks about happens twice a year. The thing that quietly costs her forty minutes every Monday never gets a vent, and it's the better build.
- **So convert every vent into a frequency question.** When she goes off about something, let her finish, then: *"How often does that actually happen?"* and *"When was the last time before this one?"* Write the number down. That single move is the difference between building for her worst day and building for her normal week.
- **Don't just ride the vent.** It's comfortable and it feels productive because she's animated and you're bonding. It's also the path of least resistance to the wrong answer. When a vent burns out, go back to Phase 2 and ask about workarounds again.
- **Ask what she's *stopped* mentioning.** Things people vent about are things they still believe could change. The `[N]` stuff — resigned, normalized, not worth complaining about anymore — never surfaces in a vent. Phase 5 is built for that; don't skip it because the earlier phases felt rich.

**Because she's a working nurse too:**

- **Ask when she does the manager half of the job.** If the honest answer is "after my shift" or "at home" or "in fifteen-minute gaps," you've found the shape of the whole problem before you've found the problem.
- **Ask what she drops when the department goes sideways** — and what it costs her to pick it back up.
- **Watch for her covering shifts herself.** A manager who ends up on the floor because she couldn't fill a hole is paying twice, and it's the kind of thing people describe as normal.

**General:**

- **Schedule it. Don't ambush her.** Ask for the time and give her the topic. Her calendar is the scarcest thing in the department.
- **Nothing that sounds like an audit.** You're a nurse asking about her workload, not staff evaluating management. If a question could read as "why is the department like this," rewrite it as "where does your time go."
- **Stay off individual employees.** Even if she goes there — and if she vents downward, she might. Let her, don't follow, and don't write it down. It's not your lane and nothing buildable lives there.
- **Expect interruptions.** It's an ED. If she gets pulled away, that's data — note what pulled her and how long it took to come back. Offer to finish later rather than rushing the end.
- **Off-shift if you can.** On-shift she's answering with one eye on the board.
- **You talk less than 20% of the time.** When she stops, wait three full seconds. She'll fill it, and the fill is the good part.
- **Paper, not a laptop.** A laptop makes it an interrogation and you'll type instead of listen.
- **Ask about the past, never the future.** "Walk me through last Tuesday" is data. "What would you want" is fiction.

---

## Live note markers

Scrawl these in the margin as she talks. They're what you'll sort by afterward.

| Mark | Means | Why it matters |
| --- | --- | --- |
| `[!]` | Emotional spike — sighing, "ugh," "I hate," a laugh at how dumb it is | Emotion marks real pain better than any description |
| `[R]` | Repeats — write down how often | Frequency beats severity for buildability |
| `[W]` | Workaround she built herself | **The loudest signal in the room** — see below |
| `[C]` | Costs real money or real time | Makes the value concrete |
| `[N]` | Normalized — "that's just how it is here" | The need she doesn't know she has |
| `[F]` | She tried to fix it and it didn't stick | Tells you how your solution will fail too |
| `[P]` | Touches PHI | Flag it now so you don't fall in love with it later |

**On `[W]`:** a workaround is a need she already priced and paid for by hand. In an ED manager's world these look like — a personal spreadsheet shadowing the official system, a group text used as a coverage board, a paper list in her pocket, a recurring phone reminder for something that isn't time-based, a whiteboard she photographs, a Word doc she retypes the same numbers into every month. She won't call any of these problems. She built them, so to her they're solutions. They are the map to what's missing.

---

## Phase 1 — Warm-up (5 min)

Get her narrating specifics, not summarizing.

- Walk me through yesterday, start to finish.
- What part of this week ate the most time?
- What took way longer than it should have?
- What's the first thing you do when you get in, and the last thing before you leave?

## Phase 2 — Workaround hunt (10 min) — *the money phase*

- Do you keep a spreadsheet for anything?
- Is there something you track on paper, or in your notes app, or by texting yourself?
- What do you set reminders for?
- Is there something you have to keep checking on just to make sure it didn't fall apart?
- What do you type in twice — once in one place, once in another?
- What do you do by hand that you're pretty sure a computer should be doing?
- Where do you keep the thing you can never find when you need it?

## Phase 3 — Frustration mining (10 min)

Aim at time and process, not people.

- What made you say "ugh" this week?
- What do you put off the longest every month?
- What's the task where you think "this again"?
- If you could delete one recurring obligation from your job forever, what is it?
- Last time you stayed late — what was it for?

## Phase 4 — ED-manager specifics

You know this world, so use it. These are seeds — cut the ones that don't fit her actual role and add the ones you already suspect.

**Wearing both hats** — start here, it's the seam most likely to hold the real problem
- When do you actually do the manager parts of the job?
- What happens to that work on a shift where you're in it clinically all day?
- What do you take home? How often?
- When the department goes sideways, what's the first thing you drop — and what does it cost to pick it back up?
- How often do you end up covering a shift yourself because you couldn't fill it?
- What do you try to get done in the gaps, and what keeps getting interrupted halfway?

**Staffing and coverage**
- How does a callout actually reach you, and what happens next?
- How do you fill a hole in the schedule at 0500?
- What's the self-scheduling process like when two people want the same thing?
- How do you keep track of who's owed what — overtime, shift swaps, floating?
- How do travelers and agency staff change what you have to track?

**Certifications, onboarding, competency**
- How do you know whose BLS/ACLS/PALS/TNCC is about to lapse?
- What happens when you find out too late?
- How do you track where a new hire is with their preceptor?
- How do you know a competency actually got signed off?

**Reporting upward**
- What do you have to send your director every month, and where do those numbers come from?
- How long does that take? What's the worst part of assembling it?
- Do you retype anything that already exists somewhere else?

**Checks, logs, and things**
- What has to get checked every shift, and how do you know it happened?
- What breaks and who do you have to chase to fix it?
- What supply runs out at the worst possible moment?

**Her own follow-through**
- How do you keep track of what you promised someone you'd get back to?
- What comes out of huddle or a committee meeting, and where does it go?
- What falls through the cracks most often?

## Phase 5 — The normalized pain (5 min) — *what she doesn't know she needs*

- What's something every ED manager just accepts as part of the job?
- What did you have to figure out yourself that nobody explained when you took this role?
- If someone stepped into your job tomorrow, what would blindside them?
- What do you wish you could just remember without having to try?

## Phase 6 — Go deep on the loudest one (10 min)

Pick the candidate with the most marks and drill. Depth here beats three more topics.

- Tell me about the **last specific time** that happened.
- What did you do about it?
- How long did it cost? How often does it happen?
- What happens if you just... don't do it?
- **Have you tried to fix this before? What happened to that?** ← the most important question on this page

That last one gives you the failure mode of your future solution. If her fix died because it needed daily upkeep, yours will die the same way. If it died because IT wouldn't approve it, that's your deployment constraint showing up early — listen closely.

---

## Never ask these

| Don't | Because |
| --- | --- |
| "Would you use an app that…" | Answer is always yes. Means nothing. |
| "What features would you want?" | She's not a designer, and it flips her into solution mode |
| "Do you think this is a good idea?" | She's your manager — she'll be encouraging regardless |
| "Wouldn't it be cool if…" | You just handed her the answer and she'll agree |
| "How often would you say, generally…" | Generalities are guesses. Ask about last Tuesday. |
| Anything about a specific employee | Not your lane, and it poisons the conversation |

---

## Notes

_Write here during. Verbatim quotes wherever you can — her exact words are worth more than your summary, for the build and for the assignment both._

```
Date:
Duration:
Setting:
Interruptions (what pulled her away, how long):




```

---

## After: pick the one

Fill this in within an hour, while it's fresh.

**Step 1 — PHI gate.** Cross out every candidate marked `[P]` before you score anything. Not eligible, no exceptions, no "we could anonymize it." List them separately for the writeup.

**Step 2 — score what's left.**

| Candidate | How often | Cost each time | `[W]` exists? | Software actually fixes it | Buildable in 2–4 weekends | She'd use it unprompted |
| --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |

Score the last four 1–5.

**The winner is usually not the biggest problem.** It's the most *frequent* one that already has a workaround and that she'd use without being reminded. A quarterly catastrophe makes a worse gift than a Tuesday-morning annoyance — she'll feel the Tuesday one gone every single week.

Four traps here:

- **Don't pick the one you walked in wanting to build.** Go back and read the box you filled in before the interview. If your pre-interview idea won, be suspicious — check whether it earned the marks or you weighted it.
- **Don't pick the loudest vent.** Check its `[R]` number. If it happens twice a year, it's a story, not a build. Frequency is the whole game.
- **Kill anything scoring low on "she'd use it unprompted."** She has no spare attention. A tool she has to remember to open is a tool she'll open twice. Prefer things that live where she already is — her phone, her email, a file she already opens.
- **Watch the deployment question early.** Where does this actually run? If the honest answer is "on a hospital machine" or "it needs a login the hospital owns," you have an IT conversation ahead of you, not a weekend project. Personal device, personal data, no network dependency is the path with no gatekeepers.

### One design constraint you already know

Whatever wins, she'll use it **standing up, on her phone, in ninety-second gaps, while being interrupted.** That's not a UI preference, it's a hard requirement:

- Every action completes in one step, or saves state and survives being abandoned mid-way
- No multi-screen wizards, no "don't forget to hit submit," nothing that punishes walking away
- Readable at a glance and at arm's length
- Works offline, or at least doesn't lose anything when the signal drops

A tool that requires ten uninterrupted minutes is a tool she will never once use. Build for the interruption, because the interruption is guaranteed.

**Chosen problem, in one sentence — in her words, not yours:**

```


```

---

## Assignment evidence

Capture these while it's fresh; this is what the servant-leadership writeup is made of.

- Date, duration, setting
- Three verbatim quotes
- **What surprised you** — the thing you'd have gotten wrong if you hadn't asked
- **The idea you walked in with, and what happened to it.** This is the thesis. Servant leadership isn't building someone a thing — it's subordinating your idea to what they actually said. If your idea survived unchanged, you probably talked too much.
- **The PHI-blocked candidates you set aside.** Choosing not to build the flashier thing because it wasn't yours to build is a real finding — arguably the strongest one available here.
- What you're building instead, and why that over the alternatives

One caution for the writeup itself: refer to her by role, not name, and keep the department unidentifiable. Same instinct as the PHI rule, applied to the paper.

---

## Next step

Bring this filled-in file back to the repo and run:

```
/mattpocock-skills:grill-with-docs
```

It'll interview *you* — hard — until "Taylor hates doing X" becomes something specific enough to build, and it leaves the reasoning in `CONTEXT.md` so you can pick this back up in three weeks without re-deriving it.

Then `/to-spec` → `/to-tickets` → `/implement` per ticket. Keep grill-with-docs through to-tickets in **one unbroken session**; don't clear context until the tickets exist.

Bring Taylor back in at the **prototype** stage, not before — build a throwaway version, put it in front of her, watch her hands, say nothing. Watching someone use a thing tells you what no interview can. It's also a second, cheaper touchpoint for the assignment.
