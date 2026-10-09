#!/usr/bin/env python3
"""Tests for the item bank.

    python3 items/test_bank.py

Plain asserts and a tiny runner — no pytest, so it runs anywhere Python and
PyYAML do. Exits non-zero on failure.

The important tests are the negative ones: they prove the verification layer
actually catches a wrong answer key and a colliding distractor, rather than
rubber-stamping whatever a template produces.
"""

from __future__ import annotations

import random
import sys
from fractions import Fraction as F
from pathlib import Path

import sympy
import yaml

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))

import templates  # noqa: F401,E402  (registers everything)
from bank import (  # noqa: E402
    MINUS, REGISTRY, Check, Item, Rejected, Template, key, options, render,
    validate,
)
from generate import check_integrity  # noqa: E402

SKILLS = HERE.parent / "curriculum" / "skills.yaml"
MISCONCEPTIONS = HERE / "misconceptions.yaml"

FAILURES: list[str] = []
TESTS: list = []


def test(fn):
    """Collect, don't run — so the header prints before the results."""
    TESTS.append(fn)
    return fn


# ── the negative tests: does verification actually bite? ──────────────────

@test
def verification_catches_a_wrong_answer_key():
    """A template that states the wrong answer must raise, not pass."""
    bad = Item(
        stem="Work out 3 + 4",
        correct=8,                              # wrong on purpose
        distractors={"m.square.doubles": 12},
        check=Check.eval("3 + 4"),
    )
    tmpl = Template(id="t", skill="num.squares",
                    misconceptions=("m.square.doubles",), fn=lambda r: bad)
    try:
        validate(bad, tmpl)
    except ValueError as exc:
        assert "VERIFICATION FAILED" in str(exc), exc
        return
    raise AssertionError("a wrong answer key was accepted")


@test
def colliding_distractor_is_rejected():
    item = Item(
        stem="Work out 3 + 4",
        correct=7,
        distractors={"m.square.doubles": 7},    # same as correct
        check=Check.eval("3 + 4"),
    )
    tmpl = Template(id="t", skill="num.squares",
                    misconceptions=("m.square.doubles",), fn=lambda r: item)
    try:
        validate(item, tmpl)
    except Rejected as exc:
        assert "coincides" in str(exc), exc
        return
    raise AssertionError("a distractor equal to the answer was accepted")


@test
def duplicate_distractors_are_rejected():
    item = Item(
        stem="Work out 3 + 4", correct=7,
        distractors={"m.square.doubles": 9, "m.neg.ignores_sign": F(9, 1)},
        check=Check.eval("3 + 4"),
    )
    tmpl = Template(id="t", skill="num.squares",
                    misconceptions=("m.square.doubles", "m.neg.ignores_sign"),
                    fn=lambda r: item)
    try:
        validate(item, tmpl)
    except Rejected as exc:
        assert "duplicates" in str(exc), exc
        return
    raise AssertionError("two options with the same value were accepted")


@test
def undeclared_misconception_is_rejected():
    item = Item(stem="Q", correct=1, distractors={"m.not.declared": 2},
                check=Check.eval("1"))
    tmpl = Template(id="t", skill="num.squares",
                    misconceptions=("m.square.doubles",), fn=lambda r: item)
    try:
        validate(item, tmpl)
    except Rejected as exc:
        assert "undeclared" in str(exc), exc
        return
    raise AssertionError("an undeclared misconception was accepted")


@test
def check_none_demands_a_reason():
    try:
        Check.none("")
    except ValueError:
        return
    raise AssertionError("Check.none accepted an empty reason")


# ── the check kinds ──────────────────────────────────────────────────────

@test
def check_kinds_accept_truth_and_reject_falsehood():
    cases = [
        (Check.eval("3 + 4"), 7, 8),
        (Check.solve("3*x + 7 - 22"), 5, 6),
        (Check.equiv("3*(x + 4)", "3*x + 12"), 0, None),
        (Check.roots("(x + 2)*(x - 5)", [-2, 5]), 0, None),
        (Check.sequence("3*n + 1", [4, 7, 10]), 0, None),
        (Check.stat("median", [7, 3, 9, 1, 5]), 5, 9),
        (Check.stat("range", [3, 8, 15, 4]), 12, 18),
        (Check.stat("mean", [4, 7, 9, 12, 13]), 9, 10),
    ]
    for chk, good, bad in cases:
        ok, detail = chk.run(good)
        assert ok, f"{chk.kind} rejected the truth: {detail}"
        if bad is not None:
            ok, _ = chk.run(bad)
            assert not ok, f"{chk.kind} accepted {bad}"

    # these three ignore `correct` entirely, so falsify their own argument
    ok, _ = Check.equiv("3*(x + 4)", "3*x + 7").run(0)
    assert not ok, "equiv accepted a false identity"
    ok, _ = Check.roots("(x + 2)*(x - 5)", [2, 5]).run(0)
    assert not ok, "roots accepted the wrong roots"
    ok, _ = Check.sequence("3*n + 2", [4, 7, 10]).run(0)
    assert not ok, "sequence accepted a wrong nth term"


# ── rendering ─────────────────────────────────────────────────────────────

@test
def rendering_is_exact_and_typographically_consistent():
    assert render(F(3, 4)) == "3/4"
    assert render(F(8, 4)) == "2", "fractions must reduce to integers"
    assert render(F(3456, 5), "money") == "£691.20"
    assert render(F(240, 1), "money") == "£240.00"
    assert render(F(71, 1000), "decimal") == "0.071"
    assert render(F(323, 10), "decimal") == "32.3"
    assert render(-56) == f"{MINUS}56", "answers use a typographic minus"
    assert render("x < -7") == f"x < {MINUS}7"
    a, b = sympy.symbols("a b")
    assert render(17 * a * b) == "17ab", f"got {render(17 * a * b)!r}"
    assert render(sympy.pi * 25) == "25π"
    assert render(3 * sympy.Symbol("x") ** 2) == "3x²"


@test
def key_treats_equal_values_as_one_option():
    assert key(F(1, 2)) == key(0.5)
    assert key(2) == key(F(4, 2))
    assert key("x < 3") != key("x > 3")


# ── the real templates ───────────────────────────────────────────────────

@test
def every_template_generates_valid_items_across_many_seeds():
    """Catches parameter ranges that only break occasionally."""
    rng = random.Random(1234)
    per = 25
    for tid, t in sorted(REGISTRY.items()):
        made = 0
        for _ in range(per * 40):
            if made >= per:
                break
            try:
                validate(t.fn(rng), t)
            except Rejected:
                continue
            made += 1
        assert made == per, f"{tid} produced only {made}/{per} usable items"


@test
def every_item_has_one_correct_option_and_no_repeated_text():
    rng = random.Random(99)
    for tid, t in sorted(REGISTRY.items()):
        for _ in range(12):
            try:
                item = t.fn(rng)
                validate(item, t)
            except Rejected:
                continue
            opts = options(item, rng)
            assert sum(o["correct"] for o in opts) == 1, tid
            assert len(opts) >= 2, f"{tid} has fewer than two options"
            texts = [o["text"] for o in opts]
            assert len(set(texts)) == len(texts), f"{tid} repeats option text: {texts}"
            for o in opts:
                assert o["text"].strip(), f"{tid} has a blank option"
                assert (o["misconception"] is None) == o["correct"], tid


@test
def unverified_templates_all_state_a_reason():
    rng = random.Random(5)
    for tid, t in sorted(REGISTRY.items()):
        item = t.fn(rng)
        if item.check.kind == "none":
            assert item.check.reason, f"{tid} is unverified with no reason"


@test
def every_template_carries_a_note():
    rng = random.Random(6)
    for tid, t in sorted(REGISTRY.items()):
        assert t.fn(rng).note.strip(), f"{tid} has no feedback note"


# ── cross-file integrity ─────────────────────────────────────────────────

@test
def templates_and_misconceptions_line_up_with_the_skill_graph():
    skills = {s["id"]: s for s in yaml.safe_load(SKILLS.open())["skills"]}
    miscs = {m["id"]: m for m in
             yaml.safe_load(MISCONCEPTIONS.open())["misconceptions"]}
    errors = check_integrity(skills, miscs)
    assert not errors, "; ".join(errors[:5])


@test
def integrity_check_catches_a_bad_reference():
    skills = {"num.squares": {}}
    miscs = {"m.square.doubles": {"skill": "num.nonexistent"}}
    errors = check_integrity(skills, miscs)
    assert any("not in skills.yaml" in e for e in errors), errors


def main() -> int:
    print(f"\nitem bank tests — {len(TESTS)} tests, {len(REGISTRY)} templates\n")
    for fn in TESTS:
        try:
            fn()
            print(f"  ok   {fn.__name__}")
        except AssertionError as exc:
            FAILURES.append(f"{fn.__name__}: {exc}")
            print(f"  FAIL {fn.__name__}: {exc}")
        except Exception as exc:                        # noqa: BLE001
            FAILURES.append(f"{fn.__name__}: {type(exc).__name__}: {exc}")
            print(f"  ERR  {fn.__name__}: {type(exc).__name__}: {exc}")
    if FAILURES:
        print(f"\n{len(FAILURES)} failure(s)")
        return 1
    print("\nall passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
