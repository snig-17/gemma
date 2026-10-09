# Curriculum — GCSE maths skill graph

The spine of the system described in [`../docs/DESIGN.md`](../docs/DESIGN.md). Everything else
(diagnostic, selection policy, paper assembly) reads this graph.

```
skills.yaml              183 skills, Foundation tier, hand-authored
validate.py              invariant checks + structural report  (CI gate)
simulate_diagnostic.py   measures the §3.4 diagnostic against this graph
schema.sql               DDL for the curriculum tables
to_sql.py                emit INSERT statements from skills.yaml
```

## Use

```bash
python3 curriculum/validate.py              # full report
python3 curriculum/validate.py --quiet      # CI: pass/fail only, non-zero on failure
python3 curriculum/validate.py --json       # machine-readable report
python3 curriculum/simulate_diagnostic.py   # diagnostic accuracy vs item budget
python3 curriculum/to_sql.py | psql "$DATABASE_URL"
```

Requires `pyyaml`. No other dependencies, deliberately — the graph algorithms
are ~40 lines of Kahn's algorithm and a BFS, and a graph library would be a
dependency for nothing.

## What is in here

183 skills across six domains, Foundation tier. **Foundation content is a
subset of Higher**, so this is the shared base — adding Higher means adding
nodes, not rebuilding.

| | |
|---|---|
| number | 46 |
| geometry | 49 |
| algebra | 38 |
| statistics | 21 |
| ratio | 19 |
| probability | 10 |

14 KS2 · 61 KS3 · 108 KS4. Max depth 11. Four roots.

67 skills are taught before KS4 but still assessed at GCSE. Those are the
`foundation` coverage bucket in DESIGN.md §3.2 — always in scope, never
filtered out, and where the diagnostic finds the real damage.

## Invariants

`validate.py` enforces these and exits non-zero on any violation:

- acyclic (Kahn's algorithm)
- every KS4 skill traces back to at least one KS2/KS3 prerequisite, so the
  diagnostic can always ground it
- no skill has more than **4** direct prerequisites — more than that and it
  isn't atomic, split it
- ids unique, no dangling prereq references, no self-edges, no duplicate
  entries within one `prereqs` list
- every KS4 skill carries a `spec_ref`
- a Foundation skill never depends on a Higher-only skill

A KS2/KS3 skill *may* carry a `spec_ref` — the GCSE spec restates plenty of
primary content (R1 time conversion, G16 area of a rectangle, S2 frequency
tables). That is reported, not an error.

## ⚠ spec_ref values are UNVERIFIED

The `N`/`A`/`R`/`G`/`P`/`S` reference letters come from the DfE *Mathematics
GCSE subject content and assessment objectives* document. AQA states that its
8300 subject content matches that document and that **the content is common to
all exam boards** — which is why the graph is board-agnostic and keys off DfE
refs rather than one board's codes.

**But every individual `spec_ref` in `skills.yaml` is my best-effort mapping
and none has been checked against the source document.** Before relying on
them:

- [ ] Get the current DfE subject content document.
- [ ] Diff the 73 refs cited here (`validate.py --json` → `spec_ref_skill_counts`)
      against the real statement list.
- [ ] Fix any that are wrong; add skills for any statement with no coverage.
- [ ] Confirm the Foundation/Higher split per statement — AQA splits content
      into "basic foundation", "additional foundation" and Higher-only columns,
      and a few of my tier assignments are guesses (exact trig values and
      inverse proportion especially).

Skill **ids** are DB keys. Once anything is live, never rename one — add a new
skill and deprecate the old.

## Adding Higher tier

Add nodes with `tier: higher`. The validator already prevents a Foundation
skill from depending on a Higher one, so the subset relationship is enforced
as you go. `num.surds` is in the file as the single worked example.

## Measured: how good is the diagnostic?

DESIGN.md §3.4 estimated "~25 items can locate a student across the graph".
`simulate_diagnostic.py` measures it against this graph: 500 synthetic
students whose mastery is generated top-down so it has a realistic frontier
shape (you don't master a skill whose prerequisites you lack), 4-option items
with 10% slip and 22% guess.

| items | balanced accuracy |
|---|---|
| 0 (prior only) | 72.7% |
| 5 | 86.4% |
| 10 | 89.1% |
| **15** | **90.4%** |
| 25 | 91.1% |
| 40 | 91.3% |

The knee is at **15–20 items**, not 25, and it plateaus hard after that. The
original estimate was conservative but about right.

Three things the simulation changed:

1. **A bug in §3.4.** The design wrote downward blame propagation as
   `P(x) ← P(x) · γ^d`, which makes *distant* descendants shrink *more* than
   near ones — backwards. Correct form is `P(x) ← P(x) · (1 − γ^d)`. Fixed in
   both the doc and the simulator.

2. **Raw accuracy is the wrong metric.** It reads ~87% on this graph, but
   that is inflated by easy negatives: deep skills are mastered by almost
   nobody, so "predict not mastered" scores 92% on them for free. Use
   **balanced accuracy** (mean of sensitivity and specificity).

3. **The metric choice reversed a conclusion.** Under raw accuracy the
   depth-based prior looked worthless (equal to a flat 0.5 prior). Under
   balanced accuracy it is clearly better — 90.4% vs 87.0% at 15 items. Had
   we shipped on raw accuracy we'd have dropped the prior for nothing.

### Caveats on those numbers

They measure the *algorithm against a model of a student*, not against
students. The synthetic generator assumes a strict prerequisite frontier,
which real learners violate — people pass topics with shaky prerequisites all
the time. Expect real performance to be worse. Treat 90% as an upper bound on
what this design can do, and re-run against real `attempt` data as soon as
there is any.
