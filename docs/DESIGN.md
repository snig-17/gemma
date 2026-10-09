# Design — coverage-aware adaptive learning platform (GCSE)

**Status:** design. The skill graph in `curriculum/` and the item bank in
`items/` are built and validated; the learner model, diagnostic, selection
policy and surfaces are unimplemented.

**Scope note.** This specifies a *new* product and does not describe the Swift app in this repository. The iOS app at the repo root is the hackathon artifact — see `CODE_REVIEW.md`. Two ideas carry forward from it: photographed work as the primary input, and Socratic tutoring that withholds answers. Everything else here is new.

---

## 1. Thesis

Every GCSE revision product is a **cram tool**. Demand spikes in April of Y11 and collapses in June. Seneca hands you a linear course and makes you pick; Save My Exams is a searchable library; Sparx and Eedi work because a *teacher* sets the tasks, so coverage is handled by a human who knows the scheme of work.

GCSE is taught over two or three years and **every school sequences the specification differently**. A student-facing product has no teacher in the loop, so it must infer what has actually been taught — and nobody does this.

Making the system coverage-aware changes what it is:

- It is usable from the first week of Y10, not March of Y11 — roughly 24 months of life per student instead of four.
- It kills the seasonality that curses the category.
- It removes the main objection a Y10 student has (*"I'll start revising later"*). You cannot say that to something that only asks about last week's lesson.
- It removes the main reason students abandon adaptive platforms: being served something never taught, which doesn't feel like challenge, it feels like failure.

**The product is a model of one student, continuously maintained.** Diagnostics, "what to do next", personalised papers, flashcards and the parent view are all *views* over that model, not separate features. Build the model well and the features fall out. Build the features separately and you get six half-products.

---

## 2. Competitive position

| Product | Shape | How it handles coverage |
|---|---|---|
| Seneca | free, ~14m users, linear courses | student picks |
| Save My Exams | paid library, examiner-written | student navigates |
| Sparx | school-licensed, >half of UK schools | teacher sets homework |
| Eedi | school-licensed diagnostic quizzes | teacher sets quizzes |

All four are either teacher-driven or coverage-blind. That is the gap.

### Eedi is both the closest competitor and a dependency

Eedi (formerly Diagnostic Questions) builds ten-question quizzes where every wrong option diagnoses a specific misconception, and ships "Eedi Tutor", a constrained AI maths tutor that activates only after a specific error. That is adjacent to this design. They sell to schools and teachers, which leaves the continuous student-facing product open.

They have also **open-sourced their Misconception Graph under CC BY 4.0** — 8,000+ maths misconceptions derived from ~200 million student responses.

**Use it.** It is larger and better validated than anything hand-built. Action items before depending on it:

- [ ] Read the actual licence file in their repository, not a summary of it.
- [ ] Confirm CC BY 4.0 permits commercial use with attribution (it does, but verify the specific release).
- [ ] Decide and document where attribution appears in-product.
- [ ] Map their codes to our skill graph; keep their IDs as the canonical key so we can take upstream updates.

---

## 3. Architecture

Six layers, bottom up. Each depends only on those below it.

```
6. Surfaces      session · practice paper · flashcards · progress map · parent view
5. Item bank     items tagged to skills, distractors tagged to misconceptions
4. Policy        what to show next (FSRS + prerequisite unblocking + exam backplan)
3. Cold start    adaptive diagnostic, graph-pruned
2. Learner model mastery × coverage × misconception state
1. Skill graph   ~250-300 atomic skills, prerequisite DAG
```

### 3.1 Skill graph

Nodes are atomic skills; edges are prerequisites (no simultaneous equations without rearranging; no rearranging without inverse operations). GCSE maths is roughly 250–300 nodes.

This is the spine. It is what makes "what should I do next" answerable rather than arbitrary, and it is why a linear course order feels stupid. **Build it by hand.** It is about a week of work and should not be generated.

Each node carries:

- spec reference (board + statement code)
- key stage it is first taught (KS2 / KS3 / KS4) — load-bearing, see §3.2
- tier (foundation / higher / both)
- assessment objective weighting (AO1/AO2/AO3)

Invariants to enforce in a test:

- the graph is acyclic
- every KS4 node is reachable from at least one KS2/KS3 node
- no node has more than ~4 direct prerequisites (if it does, it isn't atomic)

### 3.2 Learner model — three independent dimensions

The central design decision: **mastery, coverage and misconception state are three separate things and must never be collapsed into one number.**

#### Mastery — Elo per (student, skill)

One ability `θ` per student per skill, one difficulty `b` per item, logistic link:

```
p_correct = σ(θ_s − b_i)              σ(x) = 1 / (1 + e^−x)

θ_s ← θ_s + K_s · (y − p_correct)
b_i ← b_i + K_i · (p_correct − y)     y ∈ {0,1}

K_s = K₀ / (1 + n_s / n₀)             decay K with attempt count to stabilise
```

Credit propagates **up** the prerequisite chain, blame does **not** propagate down:

- correct at `s` → raise ancestors (prerequisites) by `γ^d · Δθ`, `d` = graph distance, `γ ≈ 0.4`. If you can do the hard thing you can probably do its prerequisites.
- incorrect at `s` → update `s` only. Failure might be `s` *or* any prerequisite; don't guess, probe. Mark ancestors as diagnosis candidates for the policy.

**Do not use neural knowledge tracing** (DKT / SAKT / SAINT). They need millions of interactions; we will have thousands, and they cannot explain themselves, which the parent and teacher views require. Bayesian Knowledge Tracing is the upgrade path if Elo saturates — not a transformer.

#### Coverage — three buckets

```
foundation   KS2/KS3 prerequisites. ALWAYS in scope.
taught       covered on this course. In scope.
not_yet      not yet taught. Out of scope by default.
```

`foundation` is not a third kind of "untaught" — it is *taught and forgotten*. Forgotten KS2/KS3 number work is the largest single cause of GCSE maths failure, and it is where the diagnostic will find the real damage. Always in scope.

`not_yet` is filtered out of new learning, with an explicit "get ahead" opt-in for the keen.

#### Misconception state — per Eedi code

```
open | resolved | recurring      + count, first_seen, last_seen
```

This is the differentiated part, and categorically different from mastery. *"73% on quadratics"* is useless. *"Drops the negative when expanding double brackets"* is actionable.

**Coverage gates availability. Mastery gates difficulty. Misconceptions drive scheduling.** Three jobs, three fields.

### 3.3 Coverage inference

Five sources, combined by weighted evidence rather than last-write-wins.

| Source | Weight | Friction |
|---|---|---|
| photographed work classified to a spec statement | 0.95 | none — byproduct of normal use |
| school pool (≥5 agreeing students, same school + year) | 0.85 | none |
| student self-report, "not yet" | 0.80 | one tap, in context |
| student self-report, "yes we've done it" | 0.70 | one tap, in context |
| scheme prior from named textbook | 0.60 | one question at signup |

Notes on each:

1. **Photo inference is the primary signal.** We already classify each photographed question to a spec statement, so every homework photo is evidence that *this was taught, roughly now*. Zero extra friction. Reconstructs the school's sequence from the student's own evidence over a few weeks.

2. **Ask in context, never in a form.** No "set up your curriculum" screen — nobody completes those. At the moment of surfacing a topic: *"Have you done this in class yet?"* Yes / Not yet. The graph amplifies each answer: a "yes" implies ancestors were covered, so each tap resolves many nodes.

3. **Negative self-report outranks positive.** A student saying "we haven't done this" is reliable. A student saying "yes we did" may be half-remembering a rushed lesson.

4. **Scheme prior.** Ask once which textbook or scheme they use — it's on their desk. Most schools run one of a handful. Load that sequence as a prior, then correct with evidence.

5. **School pooling is a real network effect, and it is local.** Once a handful of students from the same school and year group are active, their coverage pools into a school-level scheme-of-work estimate, and the next student from that school inherits it on day one. Most B2C edtech has no network effect at all — every user is independent, so there is nothing to defend. Here each school gets better the more students from that school use it, so the data moat and word-of-mouth point the same direction.

Accumulating how N English schools actually sequence GCSE maths produces a dataset neither the exam boards nor the publishers hold.

**Compliance:** pooling by school means storing which school a child attends. Keep it strictly aggregate — no student ever sees another student's data, and the pooled estimate must not be invertible to an individual (hence the ≥5 threshold). Declare it plainly in the privacy notice. Fine to do; not fine to do quietly.

### 3.4 Cold start — the adaptive diagnostic

The demo that sells the product. *"Twenty minutes and it knew exactly what was wrong with me"* is the thing a student screenshots.

**Measured against the real graph** by `curriculum/simulate_diagnostic.py`
(183 Foundation skills, 500 synthetic students): the knee is at **15–20 items**,
reaching 90.4% balanced accuracy at 15 and plateauing at ~91% by 25. Baseline
with no items, prior alone, is 72.7%. See `curriculum/README.md` for the table
and the caveats — chiefly that this measures the algorithm against a *model*
of a student, so treat ~90% as an upper bound.

Judge it on **balanced accuracy** (mean of sensitivity and specificity), never
raw accuracy: raw reads ~87% on this graph but is inflated by easy negatives on
deep skills almost nobody masters, and under raw accuracy the depth prior below
looks worthless when it is in fact worth ~3.4 points.

Naive per-skill testing needs 250 items. The prerequisite DAG makes it a search problem instead — a correct answer deep in the graph is strong evidence about everything upstream.

```
initialise  P(mastered | skill) from year-group + tier prior
            coverage from scheme prior if known

while items_used < budget and max_uncertainty > threshold:
    # pick the item with the most graph leverage
    candidates = skills where coverage in (taught, foundation)
    score(s)   = (1 − |P(s) − 0.5| · 2)          # uncertainty, peaks at 0.5
               × unresolved_ancestors(s) + unresolved_descendants(s)
    ask item for argmax score(s)

    on correct:
        P(s) ← high
        for each ancestor a at distance d:  P(a) ← P(a) + (1−P(a)) · γ^d
    on incorrect:
        P(s) ← low
        for each descendant x at distance d:  P(x) ← P(x) · (1 − γ^d)
        # ancestors unchanged — descend toward prerequisites next
        push ancestors onto probe queue
```

`γ ≈ 0.55`. Note the asymmetry in form: credit adds a decaying share of the
remaining gap, blame multiplies by a decaying factor. Both must have an effect
that **shrinks** with distance. An earlier draft of this document wrote the
descendant rule as `P(x) ← P(x) · γ^d`, which makes distant descendants shrink
*more* than near ones — backwards, and caught only by implementing it.

It is a binary search down the prerequisite DAG. Two further points:

- **Use diagnostic multiple choice**, every distractor mapped to an Eedi misconception. A wrong answer then yields the error, not just a zero — far more information per item than free response.
- **Seed coverage at the same time.** Items are only drawn from `taught`/`foundation`, and a handful of structural probes ("have you done trigonometry? vectors? quadratics?") partition the spec fast.

### 3.5 Selection policy — "what to bring up"

```
candidates = skills where
      coverage ∈ (taught, foundation)
   OR skill is a prerequisite of a taught skill        # always unblockable

rank, highest first:
   1. misconception reviews due            (FSRS, see below)
   2. unmastered prerequisites blocking a taught skill
   3. taught skills with low mastery
   4. spaced review of secure taught skills
   5. next skill in the school's predicted sequence    (new learning)

subject to:
   - exam-date backplan: remaining spec coverage / weeks remaining
   - session length from the student's stated minutes/day
   - no more than 2 consecutive items on the same skill
```

That ranking is close to the whole product.

**Every choice must be explainable in one line**, surfaced in the UI: *"You're seeing this because you made error M1842 twice and it's due for review."* The feeling of intelligence comes from the explanation, not the algorithm. This is what Seneca lacks.

#### Spaced retrieval — FSRS, attached to misconceptions

Use **FSRS** (open source, what Anki moved to, well validated). Do not invent an interval schedule.

One important deviation from standard flashcard practice: **scheduling state lives on the (student, misconception) pair, not on a card.** Any item whose distractor set covers that misconception counts as a review of it.

Grade mapping:

| Outcome | FSRS grade |
|---|---|
| avoided the misconception cleanly, first try | Good / Easy |
| correct, but slowly or after a hint | Hard |
| fell for the same misconception again | Again |

That is what makes it a learning system rather than a deck of cards.

### 3.6 Item bank — the real cost and the real moat

Every layer above is worthless without items tagged to skills *and* misconceptions, with distractors that diagnose.

#### Legal constraint — resolve before building

**Exam board past papers are the boards' copyright.** AQA, Pearson and OCR each set their own terms, and commercial redistribution generally requires a licence. This is precisely why Save My Exams pays examiners to author original questions.

- [ ] Read each board's copyright and reuse terms directly.
- [ ] Do not put a single past-paper question into the product until that is settled in writing.

Nothing in this document should be read as legal advice; this needs checking at source.

#### Generation pipeline

```
skill + target misconceptions
   → LLM generates stem, correct answer, and one distractor per misconception
   → symbolic verification (SymPy):
        · the stated answer is actually correct
        · each distractor is the exact output of the error it claims
          (simulate the misconception, compare)
   → reject and regenerate on failure
   → human review of a sample before any item goes live
   → calibrate b from live responses (Elo on the item side)
```

Generated maths items are wrong more often than people expect, and **one wrong answer key destroys trust permanently** — a student who is marked wrong when they were right does not come back. The symbolic check is not optional, and neither is sampled human review.

The misconception-simulation check is the clever part: if the claimed misconception is "forgets to distribute the negative", then applying that specific error to the stem must produce exactly that distractor. If it doesn't, the tag is a lie and the diagnostic signal is noise.

### 3.7 Surfaces

Each is a view over the model. None holds its own logic.

**Daily session.** Due misconception reviews + unblocking prerequisites + one new skill. Length from stated minutes/day. Every item carries its one-line reason.

**Personalised practice paper.** Constrained assembly:

```
select N items to:
   match the real paper's topic and AO proportions
   weight toward low-mastery taught skills
   include ≥1 item per open misconception (capped)
   target predicted score in the 55–75% band:
       Σ σ(θ_s − b_i) / N  ∈ [0.55, 0.75]
   coverage filter: taught + foundation only
```

Greedy fill by topic quota, then local swaps to tune predicted score. Do not reach for an ILP.

Target the 55–75% band deliberately: a paper you score 20% on is not a diagnostic, it's a reason to quit. Mark with **method marks and mark-scheme language** — where M1 and A1 are won and lost. This is the best feature and no incumbent has it.

**Flashcards.** Generated from the student's actual errors, scheduled by FSRS against misconceptions. Not a deck you build — a deck your mistakes build.

**Progress map.** Coverage filtering must **not** silently hide the specification. By spring of Y11 the student needs to see what is still untaught, because that is a conversation to have with their teacher. Show it: *"you've covered 61% of the spec — here's what's left, and here's what your school usually teaches next."* This is also the most compelling thing to put in front of a parent, and far more honest than a predicted grade.

**Parent view.** Written from the learner record only, never from conversation transcripts. Plain English. Carried over from the existing build.

---

## 4. Data model

Indicative, not final. Postgres assumed.

```sql
-- §3.1 skill graph
skill (
  id              text primary key,
  board           text not null,
  spec_ref        text not null,
  title           text not null,
  key_stage       text not null check (key_stage in ('KS2','KS3','KS4')),
  tier            text not null check (tier in ('foundation','higher','both')),
  ao_weighting    jsonb
);

skill_prereq (
  skill_id        text references skill(id),
  prereq_id       text references skill(id),
  primary key (skill_id, prereq_id)
  -- acyclicity enforced in application + test, not by the DB
);

-- Eedi codes are the canonical key so upstream updates can be taken
misconception (
  id              text primary key,          -- Eedi graph id
  skill_id        text references skill(id),
  description     text not null,
  source          text not null default 'eedi-cc-by-4.0'
);

-- §3.2 learner model: three dimensions, one row
student_skill (
  student_id          uuid not null,
  skill_id            text references skill(id),
  -- mastery
  elo                 real not null default 0,
  attempts            int  not null default 0,
  -- coverage
  coverage            text not null default 'not_yet'
                        check (coverage in ('foundation','taught','not_yet')),
  coverage_source     text,                  -- photo|self_report|school_pool|scheme_prior
  coverage_confidence real,
  coverage_set_at     timestamptz,
  first_seen_at       timestamptz,
  primary key (student_id, skill_id)
);

student_misconception (
  student_id      uuid not null,
  misconception_id text references misconception(id),
  status          text not null check (status in ('open','resolved','recurring')),
  occurrences     int  not null default 1,
  first_seen      timestamptz not null,
  last_seen       timestamptz not null,
  -- FSRS state lives here, not on a card (§3.5)
  fsrs_stability  real,
  fsrs_difficulty real,
  due_at          timestamptz,
  primary key (student_id, misconception_id)
);

-- §3.3 pooled scheme of work. n_students >= 5 before use.
school_scheme (
  school_id       uuid not null,
  year_group      int  not null,
  skill_id        text references skill(id),
  taught_by_week  int,
  n_students      int  not null,
  confidence      real not null,
  primary key (school_id, year_group, skill_id)
);

-- §3.6 items
item (
  id              uuid primary key,
  skill_id        text references skill(id),
  stem            text not null,
  options         jsonb not null,   -- [{text, correct, misconception_id}]
  difficulty_b    real not null default 0,
  verified_at     timestamptz,      -- symbolic check passed
  reviewed_by     text,             -- sampled human review
  provenance      text not null     -- generated|authored
);

-- the evaluation substrate (§5). Append-only. Never delete.
attempt (
  id              bigserial primary key,
  student_id      uuid not null,
  item_id         uuid references item(id),
  skill_id        text references skill(id),
  correct         bool not null,
  chosen_option   int,
  misconception_id text,            -- null if correct or unclassified
  latency_ms      int,
  hinted          bool not null default false,
  context         text not null,    -- diagnostic|session|paper|photo
  created_at      timestamptz not null default now()
);
```

`coverage_source` + `coverage_confidence` are load-bearing. Students misremember what they have been taught constantly, so photo evidence and pooled data must be able to override a student's self-report.

`attempt` is the most valuable table in the system. It is the training data, the evaluation set, and the audit trail. Append-only.

---

## 5. Evaluation — the number that says whether this is real

Hold out each student's next attempt and predict correct / incorrect.

```
split:      by time, never randomly (predict future from past)
metrics:    AUC and log-loss on next-attempt correctness
secondary:  misconception durability — of misconceptions marked resolved,
            what fraction recur within 30 days
```

Beat all three baselines:

1. item difficulty alone (ignore the student)
2. the student's running overall accuracy (ignore the skill)
3. the student's running per-skill accuracy (ignore the graph)

**If the learner model cannot beat baseline 3, the personalisation is theatre** and this is Seneca with better copy. Measurable offline on a few thousand interactions, with no users. Track it from week one — it is also the thing that makes this defensible in an academic or funding conversation.

Coverage inference needs its own check: on students where the true scheme of work is known (ask three schools for theirs), measure precision and recall of inferred `taught`. Precision matters more than recall — serving an untaught topic is the failure mode that loses the user.

---

## 6. v1 scope

Shippable in a term by one person, and contains the whole loop.

**In:**

- one subject, one tier — GCSE maths, pick Foundation *or* Higher
- skill graph, hand-built
- Eedi misconception graph imported
- adaptive diagnostic
- learner model (all three dimensions)
- coverage inference: photo + in-context ask + scheme prior
- daily session with one-line reasons
- personalised practice paper with method-mark feedback
- flashcards from errors, FSRS against misconceptions
- progress map
- parent view

**Out (and why):**

| Cut | Reason |
|---|---|
| LMS / Google Classroom / Satchel integration | admin-gated; requires a school deal. Photo capture replaces it at no real loss |
| daily timetable sync | nobody maintains a manual timetable. Two questions — exam date, minutes/day — give the same benefit |
| school pooling | needs density first. Design the schema for it now (§4), switch on later |
| multi-subject | the graph is the work; one subject proves the model |
| social / leaderboards | not the differentiator, and raises the safeguarding surface |
| voice and whiteboard | from the iOS prototype. Revisit as an iPad companion once there are paying users |

---

## 7. Build order

1. ~~**Skill graph** for the chosen tier, with the invariant tests.~~ **Done** —
   183 Foundation skills in `curriculum/skills.yaml`, invariants enforced by
   `curriculum/validate.py`, loadable via `curriculum/to_sql.py`. Outstanding:
   the `spec_ref` values are unverified against the DfE document.
2. **Import the Eedi graph**, map to skills, settle attribution. Blocked on the licence checklist in §2.
3. ~~**Item generation + symbolic verification.**~~ **Partly done** — 55 templates over 48 of 183 skills in `items/`, with 66 misconceptions and independent verification. Key correction to §3.6: a misconception is implemented as an *executable transformation*, so distractors are built by running the error and need no LLM. Outstanding: diagram items, free-text reasoning, multi-mark method marks, and difficulty calibration (`difficulty_b` is 0 for everything until real responses calibrate it, so the paper assembly in §3.7 cannot yet hit its target score band).
4. **`attempt` logging and the evaluation harness** — before the model, so there is never a period of flying blind.
5. **Elo mastery model**, check against the three baselines.
6. **Diagnostic** using graph pruning.
7. **Selection policy** + daily session.
8. **Paper assembly** and the progress map.

Steps 4 and 5 are inverted relative to instinct on purpose. Build the measurement before the thing being measured.

---

## 8. Open questions and risks

**Blocking, resolve before building:**

- Exam board copyright on past papers (§3.6). Unresolved.
- Eedi licence terms read at source, not summarised (§2).

**Design risks:**

- *Coverage cold start.* Week one you know nothing. Mitigated by scheme prior + structural probes, but the first session is the weakest moment and it is also the only one most users will ever see.
- *"Taught" ≠ "taught well".* A rushed single lesson registers identically to a thorough unit. Coverage gates availability, mastery gates difficulty — keeping them separate contains this, but does not solve it.
- *Generated item quality.* The symbolic check catches wrong answer keys. It does not catch items that are correct but badly worded, culturally odd, or trivially guessable. Sampled human review is the only answer and it does not scale for free.
- *Misconception tagging from free-form work.* Classifying a photographed handwritten attempt to a specific Eedi code is much harder than scoring multiple choice. Expect low accuracy initially; prefer "unclassified" over a confident wrong tag, since a wrong tag poisons the schedule.

**Unvalidated market assumptions, stated plainly:**

- That coverage-awareness is a reason to pay. Untested.
- That students will photograph their work often enough to drive coverage inference. Untested, and the whole design rests on it.
- That misconception-led teaching works at GCSE scale. Eedi's "90% resolved" figure is a company claim, its KS3 result is not GCSE, and the EEF trial of its predecessor never collected its primary outcome because of Covid. **There is no independent evidence this approach raises GCSE attainment.** That cuts both ways — it is an unproven market, which is why it is still open.

---

## 9. Prior art worth reading before building

- Eedi / Diagnostic Questions, and Craig Barton's work on diagnostic multiple choice where every distractor is a known error.
- FSRS — the scheduler, and the research notes on why it beats SM-2.
- Bayesian Knowledge Tracing — the upgrade path from Elo.
- EEF's 16–19 research agenda, which names EdTech and AI as a 2026 priority theme.
