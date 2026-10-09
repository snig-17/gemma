# Items — diagnostic question bank

Implements [`../docs/DESIGN.md`](../docs/DESIGN.md) §3.6. Every item is 4-option-style
multiple choice where **each wrong option is the output of a specific
misconception**, so a wrong answer yields a diagnosis rather than a zero.

```
misconceptions.yaml   66 misconceptions, each tied to a skill
bank.py               framework: rendering, verification, validation
templates.py          55 generators
generate.py           generate + verify + emit JSON   (CI gate)
test_bank.py          14 tests                        (CI gate)
```

## Use

```bash
python3 items/generate.py                                   # full report
python3 items/generate.py --quiet                           # CI
python3 items/generate.py --per-template 20 --out bank.json
python3 items/test_bank.py
```

Needs `pyyaml` and `sympy`.

## The idea that makes this cheap

**A misconception is an executable transformation, not a label.**

A template picks parameters, derives the correct answer, then derives each
distractor by *running the specific error*. So the distractor → misconception
mapping is true **by construction** and cannot drift out of sync with its tag.
The correct answer is then verified down an **independent path** — SymPy
solving the equation, re-evaluating the stem's arithmetic, or the stdlib
`statistics` module.

The consequence is that most of the Foundation tier needs **no LLM**: no
hallucination risk, no per-item cost, unlimited items per template, and the
whole bank is checkable in CI. The design doc assumed LLM generation plus a
verification pass; that is still needed for *contextual word problems*, which
are a later layer. Nothing here depends on it.

## Current state

| | |
|---|---|
| templates | 55 |
| misconceptions catalogued | 66 |
| misconceptions exercised by a template | 65 |
| skills covered | **48 of 183** |
| items independently verified | 424 of 440 |

Skill coverage is the honest number to watch: **48 of 183**, concentrated in
number and algebra where procedural generation works best. Uncovered areas are
mostly those needing diagrams (constructions, loci, transformations, plans and
elevations) or free-text reasoning (angle justification, comparing
distributions). Those need a different item type, not more templates.

`m.sf.counts_from_decimal_point` has no template: every instance I could
construct collided with another misconception's answer. Left catalogued and
reported rather than forced.

## Verification

Each template declares a `Check`. The kinds, and what each is independent of:

| kind | verifies by | independent of |
|---|---|---|
| `solve` | solving the equation for the unknown | the template picking the root first |
| `eval` | re-evaluating the stem's arithmetic | the template's own computation |
| `equiv` | expanding `a − b` to zero | how the answer was written |
| `roots` | solving and comparing the root set | the template's sign reasoning |
| `sequence` | substituting n = 1, 2, 3 … | the template's nth-term algebra |
| `stat` | stdlib `statistics` | the template's own sorting and summing |
| `none` | nothing — **requires a stated reason** | — |

`Check.none` demands a reason, and every unverified item is listed in the
report. Two templates use it, both for a real reason: an inequality's
*direction* is not a value, and in standard form both options are numerically
equal so correctness is normalisation of the mantissa, not the number.

A failing check is **not** treated as an unlucky instance — it raises and stops
the build, because it means the template is wrong. That is not theoretical: it
caught a genuine bug on the first run, where the significant-figures template
constrained the wrong digit (for `0.0abc` to 2 s.f. the deciding digit is `c`,
not `b`).

### Rejection vs failure

A `Rejected` instance is normal: some parameter choices make an error produce
the right answer by accident. `generate.py` resamples and reports the rejection
rate per template — a high rate means the ranges are badly chosen. Three
templates were tightened this way: `(2,2)` makes `base^(p·q)` equal
`base^(p+q)`, and a random five-element list often has its true median already
in the middle slot.

## Form-valued answers

Some answers are a **form**, not a value — and mathematical comparison is then
the wrong test:

- `6(2x + 3)` and `3(4x + 6)` are *identical numbers*, so the "factorise
  fully" item cannot compare options by value. It compares them as text, and
  uses `Check.equiv` to confirm the correct form really does equal the
  original.
- `4.62 × 10³` and `46.2 × 10²` are the same number. Correctness is whether
  the mantissa is normalised, which is structural.

Any item whose answer is an algebraic expression is therefore string-valued.
That also removes an accidental tell: SymPy's term ordering rendered one option
as `24 - 8x` and another as `-8x - 24`, so the options didn't share a layout
and the odd one out was guessable.

## Presentation

Verification says nothing about whether an item *reads* correctly, and reading
the generated output found five bugs nothing else would have caught:
`17a*b` instead of `17ab`; `3456/5` where a price was wanted; `71/1000` for a
rounding answer; inconsistent term order; and ASCII hyphens in the options
against typographic minus in the stems.

Hence `fmt` on each item — `auto`, `decimal` or `money` — and a rendering layer
that is exact throughout (`Fraction` and `Decimal`, never a float). **Generate
a sample and read it** after touching any template. `generate.py --out` exists
for that.

## Eedi

`eedi_id` on every misconception is reserved for mapping onto Eedi's open
Misconception Graph — 8,000+ misconceptions derived from ~200m real responses,
CC BY 4.0. All null for now; that import is blocked on the licence checklist in
DESIGN.md §2, and the graph was not reachable from the build environment.

Once mapped, **Eedi's id becomes the canonical key** and ours becomes an alias.
Their set is far larger and validated against real student data, so the 66 here
are a bootstrap, not an asset to defend.

## Adding a template

1. Add the misconception to `misconceptions.yaml` with the skill it belongs to.
   The test for inclusion: *can you write a function that applies this error
   and produces a definite wrong answer?* If not, it is too vague.
2. Add a generator to `templates.py`. Derive distractors by executing the
   error. Use `Fraction`, never float. Set `fmt` if the answer is money or a
   decimal.
3. Give it a `Check` down a path independent of your own working.
4. Write a `note` — it is the feedback the student sees.
5. Run `generate.py` and read a sample; run `test_bank.py`.

Integer ratios in check expressions (`115/100`, not `1.15`) keep SymPy in exact
arithmetic.

## What is not covered

- **Diagram items** — constructions, loci, transformations, plans and
  elevations, reading a graph. Needs an SVG-generating item type.
- **Free-text reasoning** — "give a reason for your answer", comparing
  distributions. Needs marking, not matching.
- **Multi-mark method-mark items.** Everything here is single-answer. The
  method-mark feedback that DESIGN.md §3.7 calls the best feature needs
  structured working, which multiple choice cannot capture.
- **Difficulty calibration.** `difficulty_b` starts at 0 for everything and
  only becomes meaningful once real responses calibrate it (DESIGN.md §3.2).
  Until then the paper assembly in §3.7 cannot hit its target score band.
