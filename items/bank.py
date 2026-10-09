"""Item generation framework.

The central idea, and the reason this needs no LLM for most of the Foundation
tier: **a misconception is an executable transformation, not a label.**

A template picks parameters, derives the correct answer, then derives each
distractor by *running the specific error*. So the distractor -> misconception
mapping is true by construction and cannot drift. The correct answer is then
verified by an **independent path** (SymPy solving, re-evaluating the stem's
arithmetic, or the stdlib `statistics` module), which catches slips in the
template's own working.

docs/DESIGN.md §3.6 described this as "simulate the misconception, compare".
Constructing the distractor from the error is that, done so it cannot rot.

An LLM is still needed for contextual word problems — a later layer. Nothing
here depends on one, so the whole bank is free, deterministic and CI-testable.
"""

from __future__ import annotations

import random
import re
import statistics as stats_mod
from dataclasses import dataclass, field
from decimal import ROUND_HALF_UP, Decimal, localcontext
from fractions import Fraction
from typing import Callable, Sequence

import sympy

PI = sympy.pi


# ── rendering ─────────────────────────────────────────────────────────────

MINUS = "−"        # typographic minus, to match the stems


def _decimal(value: Fraction, places: int | None = None) -> str:
    """Exact decimal string for a terminating fraction."""
    with localcontext() as ctx:
        ctx.prec = 28
        dec = Decimal(value.numerator) / Decimal(value.denominator)
    if places is not None:
        dec = dec.quantize(Decimal(1).scaleb(-places), rounding=ROUND_HALF_UP)
        return f"{dec:f}"
    text = f"{dec.normalize():f}"
    return text


def render(value, fmt: str = "auto") -> str:
    """Render an answer for display. Exact — never a float approximation.

    `fmt` picks the presentation, because the same number wants different
    shapes in different questions: 3456/5 is right for a fraction question
    and wrong for a price.
    """
    if isinstance(value, str):
        return value.replace("-", MINUS)
    if isinstance(value, bool):
        return str(value)

    if isinstance(value, (int, Fraction)) or (
        isinstance(value, sympy.Expr) and value.is_Rational
    ):
        frac = (value if isinstance(value, Fraction)
                else Fraction(value) if isinstance(value, int)
                else Fraction(int(value.p), int(value.q)))
        if fmt == "money":
            return "£" + _decimal(frac, 2)
        if fmt == "decimal":
            return _decimal(frac).replace("-", MINUS)
        if frac.denominator == 1:
            return str(frac.numerator).replace("-", MINUS)
        return f"{frac.numerator}/{frac.denominator}".replace("-", MINUS)

    if isinstance(value, float):
        text = str(int(value)) if value == int(value) else f"{value:g}"
        return text.replace("-", MINUS)

    if isinstance(value, sympy.Expr):
        text = sympy.sstr(value)
        # 3*x -> 3x, a*b -> ab, 25*pi -> 25π, x**2 -> x²
        text = re.sub(r"(?<=[0-9a-zA-Z)])\*(?=[a-zA-Z(])", "", text)
        text = text.replace("pi", "π").replace("sqrt", "√")
        text = re.sub(r"\*\*2\b", "²", text)
        text = re.sub(r"\*\*3\b", "³", text)
        return text.replace("-", MINUS)

    return str(value)


def key(value) -> str:
    """Canonical form for comparing two answers.

    Options collide if they are mathematically equal, so 1/2 and 0.5 are the
    same option and must not both appear.
    """
    if isinstance(value, str):
        return f"s:{value.strip()}"
    if isinstance(value, float):
        # Normalise to a rational, or 0.5 and Fraction(1, 2) would read as
        # two distinct options when they are the same number.
        value = Fraction(value).limit_denominator(10 ** 6)
    try:
        return f"n:{sympy.nsimplify(sympy.sympify(value))}"
    except Exception:                                   # noqa: BLE001
        return f"r:{render(value)}"


# ── verification ──────────────────────────────────────────────────────────

@dataclass(frozen=True)
class Check:
    """How to verify the correct answer by a path independent of how the
    template constructed it.

    Every template must supply one. `none` is allowed but demands a reason,
    so unverified items show up in the report instead of hiding.
    """

    kind: str
    expr: str = ""
    other: str = ""
    var: str = "n"
    values: tuple = ()
    data: tuple = ()
    reason: str = ""

    # -- constructors ------------------------------------------------------

    @staticmethod
    def solve(expr: str, var: str = "x") -> "Check":
        """`expr` = 0 has the correct answer as a root.

        The template picks the root and builds the equation around it; this
        goes the other way and solves.
        """
        return Check("solve", expr=expr, var=var)

    @staticmethod
    def eval(expr: str) -> "Check":
        """`expr` evaluates to the correct answer. Pass the arithmetic as it
        appears in the stem so SymPy re-does the computation."""
        return Check("eval", expr=expr)

    @staticmethod
    def equiv(original: str, answer: str) -> "Check":
        """Two algebraic expressions are identically equal — for 'simplify',
        'expand' and 'factorise', where the answer is an expression."""
        return Check("equiv", expr=original, other=answer)

    @staticmethod
    def roots(expr: str, values: Sequence, var: str = "x") -> "Check":
        """`values` are exactly the roots of `expr` = 0."""
        return Check("roots", expr=expr, values=tuple(values), var=var)

    @staticmethod
    def sequence(expr: str, terms: Sequence[int], var: str = "n") -> "Check":
        """Substituting n = 1, 2, 3 ... into `expr` reproduces `terms`."""
        return Check("sequence", expr=expr, values=tuple(terms), var=var)

    @staticmethod
    def stat(which: str, data: Sequence) -> "Check":
        """A list statistic, computed by the stdlib `statistics` module —
        independent of the template's own sorting or summing."""
        if which not in {"mean", "median", "mode", "range"}:
            raise ValueError(f"unsupported statistic {which!r}")
        return Check("stat", expr=which, data=tuple(data))

    @staticmethod
    def none(reason: str) -> "Check":
        if not reason:
            raise ValueError("Check.none requires a reason")
        return Check("none", reason=reason)

    # -- execution ---------------------------------------------------------

    def run(self, correct) -> tuple[bool, str]:
        try:
            return getattr(self, f"_{self.kind}")(correct)
        except AttributeError:
            return False, f"unknown check kind {self.kind!r}"
        except Exception as exc:                        # noqa: BLE001
            return False, f"{type(exc).__name__}: {exc}"

    def _none(self, correct):
        return True, f"UNVERIFIED: {self.reason}"

    def _solve(self, correct):
        roots = sympy.solve(sympy.sympify(self.expr), sympy.Symbol(self.var))
        if not roots:
            return False, f"no solution for {self.expr!r}"
        want = sympy.sympify(correct)
        if any(sympy.simplify(r - want) == 0 for r in roots):
            return True, "solved"
        return False, f"roots {roots} exclude {correct}"

    def _eval(self, correct):
        got = sympy.sympify(self.expr)
        want = sympy.sympify(correct)
        if sympy.simplify(got - want) == 0:
            return True, "evaluated"
        return False, f"{self.expr!r} = {got}, template said {correct}"

    def _equiv(self, correct):
        a = sympy.sympify(self.expr)
        b = sympy.sympify(self.other)
        if sympy.simplify(sympy.expand(a - b)) == 0:
            return True, "equivalent"
        return False, f"{self.expr!r} is not identically {self.other!r}"

    def _roots(self, correct):
        found = sympy.solve(sympy.sympify(self.expr), sympy.Symbol(self.var))
        want = {sympy.simplify(sympy.sympify(v)) for v in self.values}
        got = {sympy.simplify(r) for r in found}
        if got == want:
            return True, "roots match"
        return False, f"roots {sorted(map(str, got))} != {sorted(map(str, want))}"

    def _sequence(self, correct):
        n = sympy.Symbol(self.var)
        expr = sympy.sympify(self.expr)
        for i, term in enumerate(self.values, start=1):
            got = expr.subs(n, i)
            if sympy.simplify(got - term) != 0:
                return False, f"term {i}: {self.expr!r} gives {got}, expected {term}"
        return True, "sequence matches"

    def _stat(self, correct):
        data = [Fraction(str(v)) for v in self.data]
        if self.expr == "mean":
            got = sum(data) / len(data)
        elif self.expr == "median":
            got = stats_mod.median(data)
        elif self.expr == "mode":
            got = stats_mod.mode(data)
        else:
            got = max(data) - min(data)
        if sympy.simplify(sympy.Rational(got) - sympy.sympify(correct)) == 0:
            return True, f"{self.expr} matches"
        return False, f"{self.expr} is {got}, template said {correct}"


# ── items and templates ───────────────────────────────────────────────────

@dataclass
class Item:
    stem: str
    correct: object
    distractors: dict[str, object]       # misconception id -> wrong answer
    check: Check
    note: str = ""                       # worked step, for feedback
    fmt: str = "auto"                    # "auto" | "decimal" | "money"


@dataclass
class Template:
    id: str
    skill: str
    misconceptions: tuple[str, ...]
    fn: Callable[[random.Random], Item]
    tags: tuple[str, ...] = field(default_factory=tuple)


REGISTRY: dict[str, Template] = {}


def template(*, id: str, skill: str, misconceptions: list[str],
             tags: list[str] | None = None):
    def wrap(fn):
        if id in REGISTRY:
            raise ValueError(f"duplicate template id {id!r}")
        REGISTRY[id] = Template(id=id, skill=skill,
                                misconceptions=tuple(misconceptions),
                                fn=fn, tags=tuple(tags or ()))
        return fn
    return wrap


# ── instance validation ───────────────────────────────────────────────────

class Rejected(Exception):
    """This instance is unusable — resample. Not a template bug."""


def validate(item: Item, tmpl: Template) -> None:
    """Checks that must hold for every emitted item.

    Rejections are normal: some parameter choices make an error produce the
    right answer by accident (a sign slip on zero). generate.py resamples and
    reports the rate per template — a high rate means badly chosen ranges.

    A failing `check` is NOT a rejection. It means the template's arithmetic
    is wrong, so it raises and stops the build.
    """
    if not item.stem.strip():
        raise Rejected("empty stem")
    if not item.distractors:
        raise Rejected("no distractors")

    declared = set(tmpl.misconceptions)
    produced = set(item.distractors)
    if produced - declared:
        raise Rejected(f"undeclared misconception(s): {sorted(produced - declared)}")

    ck = key(item.correct)
    seen = {ck: "correct"}
    for mid, value in item.distractors.items():
        k = key(value)
        if k == ck:
            # The item exists because the error gives a DIFFERENT answer.
            # If it doesn't, the item diagnoses nothing.
            raise Rejected(f"{mid} coincides with the correct answer")
        if k in seen:
            raise Rejected(f"{mid} duplicates the option from {seen[k]}")
        seen[k] = mid

    ok, detail = item.check.run(item.correct)
    if not ok:
        raise ValueError(f"{tmpl.id}: VERIFICATION FAILED — {detail}")


def options(item: Item, rng: random.Random) -> list[dict]:
    """Shuffled options, each carrying the misconception it diagnoses."""
    opts = [{"text": render(item.correct, item.fmt), "correct": True,
             "misconception": None}]
    for mid, value in item.distractors.items():
        opts.append({"text": render(value, item.fmt), "correct": False,
                     "misconception": mid})
    rng.shuffle(opts)
    return opts
