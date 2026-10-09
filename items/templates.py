"""Item templates.

Each template picks parameters, derives the correct answer, and derives each
distractor by *executing* a specific misconception. Every template supplies a
`Check` that verifies the correct answer by an independent path.

Conventions:
  · Use Fraction, never float, so answers are exact.
  · Check expressions use integer ratios (115/100, not 1.15) to keep SymPy
    in exact arithmetic.
  · Parameter ranges should be chosen so distractors rarely collide with the
    correct answer. generate.py reports the rejection rate per template.
"""

from __future__ import annotations

import random
from fractions import Fraction as F

import sympy

from bank import PI, Check, Item, template

# ══════════════════════════════════════════════════════════════════════════
# NUMBER — negatives, order of operations
# ══════════════════════════════════════════════════════════════════════════


@template(id="num.neg.sub_negative", skill="num.neg.add_sub",
          misconceptions=["m.neg.subtract_as_add", "m.neg.ignores_sign"])
def neg_sub_negative(rng):
    a = rng.randint(2, 15)
    b = rng.randint(2, 12)
    return Item(
        stem=f"Work out  −{a} − (−{b})",
        correct=-a + b,
        distractors={
            "m.neg.subtract_as_add": -a - b,
            "m.neg.ignores_sign": a - b,
        },
        check=Check.eval(f"-{a} - (-{b})"),
        note=f"Subtracting −{b} is the same as adding {b}.",
    )


@template(id="num.neg.product", skill="num.neg.mul_div",
          misconceptions=["m.neg.product_stays_negative"])
def neg_product(rng):
    a = rng.randint(3, 12)
    b = rng.randint(3, 9)
    return Item(
        stem=f"Work out  −{a} × −{b}",
        correct=a * b,
        distractors={"m.neg.product_stays_negative": -a * b},
        check=Check.eval(f"(-{a})*(-{b})"),
        note="A negative multiplied by a negative gives a positive.",
    )


@template(id="num.order_of_ops.mixed", skill="num.order_of_ops",
          misconceptions=["m.bidmas.left_to_right", "m.bidmas.add_before_multiply"])
def order_of_ops(rng):
    a = rng.randint(12, 30)
    b = rng.randint(2, 6)
    c = rng.randint(2, 7)
    d = rng.randint(2, 9)
    return Item(
        stem=f"Work out  {a} − {b} × {c} + {d}",
        correct=a - b * c + d,
        distractors={
            "m.bidmas.left_to_right": (a - b) * c + d,
            "m.bidmas.add_before_multiply": a - b * (c + d),
        },
        check=Check.eval(f"{a} - {b}*{c} + {d}"),
        note="Multiplication is done before addition and subtraction.",
    )


# ══════════════════════════════════════════════════════════════════════════
# NUMBER — fractions
# ══════════════════════════════════════════════════════════════════════════


@template(id="num.frac.add_same_denom", skill="num.frac.add_sub_same",
          misconceptions=["m.frac.add_denominators"])
def frac_add_same(rng):
    d = rng.choice([5, 7, 8, 9, 11, 12])
    a = rng.randint(1, d - 2)
    b = rng.randint(1, d - a - 1)
    return Item(
        stem=f"Work out  {a}/{d} + {b}/{d}",
        correct=F(a + b, d),
        distractors={"m.frac.add_denominators": F(a + b, 2 * d)},
        check=Check.eval(f"{a}/{d} + {b}/{d}"),
        note="The denominator stays the same; only the numerators are added.",
    )


@template(id="num.frac.add_diff_denom", skill="num.frac.add_sub_diff",
          misconceptions=["m.frac.add_across", "m.frac.common_denom_only"])
def frac_add_diff(rng):
    d1, d2 = rng.sample([3, 4, 5, 6, 8], 2)
    n1 = rng.randint(1, d1 - 1)
    n2 = rng.randint(1, d2 - 1)
    lcm = sympy.ilcm(d1, d2)
    return Item(
        stem=f"Work out  {n1}/{d1} + {n2}/{d2}",
        correct=F(n1, d1) + F(n2, d2),
        distractors={
            "m.frac.add_across": F(n1 + n2, d1 + d2),
            "m.frac.common_denom_only": F(n1 + n2, lcm),
        },
        check=Check.eval(f"{n1}/{d1} + {n2}/{d2}"),
        note=f"Write both over {lcm}, then add the numerators.",
    )


@template(id="num.frac.multiply", skill="num.frac.multiply",
          misconceptions=["m.frac.cross_multiply"])
def frac_multiply(rng):
    n1, d1 = rng.randint(1, 5), rng.randint(2, 7)
    n2, d2 = rng.randint(1, 5), rng.randint(2, 7)
    if n1 >= d1 or n2 >= d2:
        n1, d1, n2, d2 = 2, 3, 3, 5
    return Item(
        stem=f"Work out  {n1}/{d1} × {n2}/{d2}",
        correct=F(n1 * n2, d1 * d2),
        distractors={"m.frac.cross_multiply": F(n1 * d2, d1 * n2)},
        check=Check.eval(f"({n1}/{d1})*({n2}/{d2})"),
        note="Multiply the numerators, then multiply the denominators.",
    )


@template(id="num.frac.divide", skill="num.frac.divide",
          misconceptions=["m.frac.divide_directly"])
def frac_divide(rng):
    n1, d1 = rng.randint(1, 5), rng.randint(2, 7)
    n2, d2 = rng.randint(1, 5), rng.randint(2, 7)
    if n1 >= d1 or n2 >= d2:
        n1, d1, n2, d2 = 3, 4, 2, 5
    return Item(
        stem=f"Work out  {n1}/{d1} ÷ {n2}/{d2}",
        correct=F(n1, d1) / F(n2, d2),
        # multiplies straight across without inverting the second fraction
        distractors={"m.frac.divide_directly": F(n1 * n2, d1 * d2)},
        check=Check.eval(f"({n1}/{d1})/({n2}/{d2})"),
        note=f"Multiply by the reciprocal: × {d2}/{n2}.",
    )


@template(id="num.frac.of_amount", skill="num.frac.of_amount",
          misconceptions=["m.frac.of_divide_by_numerator"])
def frac_of_amount(rng):
    d = rng.choice([3, 4, 5, 6, 8])
    n = rng.randint(1, d - 1)
    amount = d * n * rng.randint(2, 9)      # keeps both answers whole
    return Item(
        stem=f"Work out  {n}/{d} of {amount}",
        correct=F(amount * n, d),
        distractors={"m.frac.of_divide_by_numerator": F(amount * d, n)},
        check=Check.eval(f"({n}/{d})*{amount}"),
        note=f"Divide by {d}, then multiply by {n}.",
    )


# ══════════════════════════════════════════════════════════════════════════
# NUMBER — rounding
# ══════════════════════════════════════════════════════════════════════════


@template(id="num.round.dp_up", skill="num.round.dp",
          misconceptions=["m.round.truncates"])
def round_dp_up(rng):
    whole = rng.randint(1, 60)
    keep = rng.randint(1, 9)
    nxt = rng.randint(5, 9)                 # forces a round UP
    tail = rng.randint(0, 9)
    value = F(whole * 1000 + keep * 100 + nxt * 10 + tail, 1000)
    return Item(
        stem=f"Round {whole}.{keep}{nxt}{tail} to 1 decimal place",
        correct=F(whole * 10 + keep + 1, 10),
        distractors={"m.round.truncates": F(whole * 10 + keep, 10)},
        check=Check.eval(f"floor({value}*10 + 1/2)/10"),
        note=f"The next digit is {nxt}, which is 5 or more, so round up.",
        fmt="decimal",
    )


@template(id="num.round.dp_down", skill="num.round.dp",
          misconceptions=["m.round.always_up"])
def round_dp_down(rng):
    whole = rng.randint(1, 60)
    keep = rng.randint(1, 8)
    nxt = rng.randint(0, 4)                 # forces a round DOWN
    tail = rng.randint(0, 9)
    value = F(whole * 1000 + keep * 100 + nxt * 10 + tail, 1000)
    return Item(
        stem=f"Round {whole}.{keep}{nxt}{tail} to 1 decimal place",
        correct=F(whole * 10 + keep, 10),
        distractors={"m.round.always_up": F(whole * 10 + keep + 1, 10)},
        check=Check.eval(f"floor({value}*10 + 1/2)/10"),
        note=f"The next digit is {nxt}, which is less than 5, so round down.",
        fmt="decimal",
    )


@template(id="num.round.sf_decimal", skill="num.round.sf",
          misconceptions=["m.sf.treats_as_dp"])
def round_sf_decimal(rng):
    # 0.0abc to 2 s.f.  The significant figures are a and b, so the digit
    # that decides the rounding is c — not b.
    a = rng.randint(1, 9)
    b = rng.randint(0, 8)                   # 9 would carry into a
    c = rng.randint(5, 9)                   # forces b to round up
    num = a * 100 + b * 10 + c              # 0.0abc = num / 10000
    # Treating "2 s.f." as "2 d.p." keeps only 0.0a, decided by b.
    as_2dp = F(a + 1, 100) if b >= 5 else F(a, 100)
    return Item(
        stem=f"Round 0.0{a}{b}{c} to 2 significant figures",
        correct=F(a * 10 + b + 1, 1000),
        distractors={"m.sf.treats_as_dp": as_2dp},
        check=Check.eval(f"floor({num}/10 + 1/2)/1000"),
        note=f"The first significant figure is {a}, the first non-zero digit.",
        fmt="decimal",
    )


# ══════════════════════════════════════════════════════════════════════════
# NUMBER — percentages, indices, factors
# ══════════════════════════════════════════════════════════════════════════


@template(id="num.pct.of_amount", skill="num.pct.of_amount",
          misconceptions=["m.pct.divides_by_percentage", "m.pct.moves_decimal_wrong"])
def pct_of_amount(rng):
    pct = rng.choice([5, 15, 20, 25, 40])
    amount = pct * rng.randint(3, 12)       # keeps amount/pct whole
    return Item(
        stem=f"Work out {pct}% of {amount}",
        correct=F(pct * amount, 100),
        distractors={
            "m.pct.divides_by_percentage": F(amount, pct),
            "m.pct.moves_decimal_wrong": F(pct * amount, 10),
        },
        check=Check.eval(f"{pct}*{amount}/100"),
        note=f"{pct}% = {pct}/100, so multiply {amount} by {pct} and divide by 100.",
    )


@template(id="num.indices.multiply_powers", skill="num.indices.laws",
          misconceptions=["m.indices.multiplies_exponents", "m.indices.multiplies_bases"])
def indices_multiply(rng):
    base = rng.choice([2, 3, 5])
    p = rng.randint(2, 4)
    q = rng.randint(2, 4)
    if p * q == p + q:          # (2,2) makes the distractor collide
        q = p + 1
    return Item(
        stem=f"Work out  {base}^{p} × {base}^{q}",
        correct=base ** (p + q),
        distractors={
            "m.indices.multiplies_exponents": base ** (p * q),
            "m.indices.multiplies_bases": (base * base) ** (p + q),
        },
        check=Check.eval(f"{base}**{p} * {base}**{q}"),
        note=f"Same base, so add the powers: {base}^{p + q}.",
    )


@template(id="num.indices.zero_power", skill="num.indices.zero_neg",
          misconceptions=["m.indices.zero_is_zero"])
def indices_zero(rng):
    base = rng.randint(2, 30)
    return Item(
        stem=f"Work out  {base}^0",
        correct=1,
        distractors={"m.indices.zero_is_zero": 0},
        check=Check.eval(f"{base}**0"),
        note="Any non-zero number to the power 0 is 1.",
    )


@template(id="num.indices.negative_power", skill="num.indices.zero_neg",
          misconceptions=["m.indices.negative_means_negative"])
def indices_negative(rng):
    base = rng.choice([2, 3, 4, 5])
    p = rng.randint(2, 3)
    return Item(
        stem=f"Work out  {base}^−{p}",
        correct=F(1, base ** p),
        distractors={"m.indices.negative_means_negative": -(base ** p)},
        check=Check.eval(f"{base}**(-{p})"),
        note=f"A negative power means the reciprocal: 1/{base}^{p}.",
    )


@template(id="num.std_form.find_power", skill="num.standard_form",
          misconceptions=["m.std_form.power_wrong_direction"])
def std_form_power(rng):
    mantissa = F(rng.randint(10, 99), 10)   # 1.0 to 9.9
    p = rng.randint(3, 6)
    value = mantissa * 10 ** p
    return Item(
        stem=f"{value} = {mantissa} × 10^n.   What is n?",
        correct=p,
        distractors={"m.std_form.power_wrong_direction": -p},
        check=Check.solve(f"{mantissa}*10**x - {value}", var="x"),
        note=f"The point moves {p} places, and the number is large, so n is positive.",
    )


@template(id="num.hcf.two_numbers", skill="num.hcf",
          misconceptions=["m.hcf_lcm.swapped"])
def hcf_two(rng):
    g = rng.choice([4, 6, 8, 9, 12])
    a = g * rng.randint(2, 6)
    b = g * rng.randint(2, 6)
    if a == b or sympy.igcd(a, b) != g:
        a, b, g = 18, 24, 6
    return Item(
        stem=f"Find the highest common factor of {a} and {b}",
        correct=sympy.igcd(a, b),
        distractors={"m.hcf_lcm.swapped": sympy.ilcm(a, b)},
        check=Check.eval(f"gcd({a}, {b})"),
        note="The HCF is the largest number that divides into both.",
    )


@template(id="num.lcm.two_numbers", skill="num.lcm",
          misconceptions=["m.lcm.multiplies_the_numbers"])
def lcm_two(rng):
    a = rng.choice([4, 6, 8, 9, 10, 12])
    b = rng.choice([6, 8, 9, 10, 14, 15])
    if sympy.igcd(a, b) == 1:
        a, b = 6, 8
    return Item(
        stem=f"Find the lowest common multiple of {a} and {b}",
        correct=sympy.ilcm(a, b),
        distractors={"m.lcm.multiplies_the_numbers": a * b},
        check=Check.eval(f"lcm({a}, {b})"),
        note=f"{a} and {b} share a factor, so the LCM is smaller than {a}×{b}.",
    )


@template(id="num.squares.value", skill="num.squares",
          misconceptions=["m.square.doubles"])
def squares(rng):
    a = rng.randint(3, 15)
    return Item(
        stem=f"Work out  {a}²",
        correct=a * a,
        distractors={"m.square.doubles": 2 * a},
        check=Check.eval(f"{a}**2"),
        note=f"{a}² means {a} × {a}.",
    )


# ══════════════════════════════════════════════════════════════════════════
# ALGEBRA — manipulation
# ══════════════════════════════════════════════════════════════════════════


@template(id="alg.collect.two_variables", skill="alg.collect_like_terms",
          misconceptions=["m.collect.combines_unlike_terms"])
def collect_terms(rng):
    a, b, c = rng.sample(range(2, 10), 3)   # distinct, so no accidental pattern
    return Item(
        stem=f"Simplify  {a}a + {b}b + {c}a",
        correct=f"{a + c}a + {b}b",
        distractors={"m.collect.combines_unlike_terms": f"{a + b + c}ab"},
        check=Check.equiv(f"{a}*a + {b}*b + {c}*a", f"{a + c}*a + {b}*b"),
        note="Only terms with the same letter can be combined.",
    )


@template(id="alg.substitute.linear", skill="alg.substitute",
          misconceptions=["m.sub.digit_concatenation"])
def substitute_linear(rng):
    a = rng.randint(2, 9)
    b = rng.randint(1, 15)
    v = rng.randint(2, 9)
    return Item(
        stem=f"Work out the value of  {a}x + {b}  when x = {v}",
        correct=a * v + b,
        distractors={"m.sub.digit_concatenation": int(f"{a}{v}") + b},
        check=Check.eval(f"{a}*{v} + {b}"),
        note=f"{a}x means {a} × {v}.",
    )


@template(id="alg.substitute.squared", skill="alg.substitute",
          misconceptions=["m.sub.squares_the_coefficient"])
def substitute_squared(rng):
    a = rng.randint(2, 6)
    v = rng.randint(2, 7)
    return Item(
        stem=f"Work out the value of  {a}x²  when x = {v}",
        correct=a * v * v,
        distractors={"m.sub.squares_the_coefficient": (a * v) ** 2},
        check=Check.eval(f"{a}*{v}**2"),
        note="Only x is squared, not the coefficient.",
    )


@template(id="alg.expand.single_positive", skill="alg.expand.single",
          misconceptions=["m.expand.first_term_only"])
def expand_single(rng):
    a = rng.randint(2, 9)
    b = rng.randint(2, 12)
    return Item(
        stem=f"Expand  {a}(x + {b})",
        correct=f"{a}x + {a * b}",
        distractors={"m.expand.first_term_only": f"{a}x + {b}"},
        check=Check.equiv(f"{a}*(x + {b})", f"{a}*x + {a * b}"),
        note=f"Multiply both terms by {a}.",
    )


@template(id="alg.expand.single_negative", skill="alg.expand.single",
          misconceptions=["m.expand.sign_not_distributed"])
def expand_single_negative(rng):
    a = rng.randint(2, 9)
    b = rng.randint(2, 12)
    return Item(
        stem=f"Expand  −{a}(x − {b})",
        correct=f"−{a}x + {a * b}",
        distractors={"m.expand.sign_not_distributed": f"−{a}x − {a * b}"},
        check=Check.equiv(f"-{a}*(x - {b})", f"-{a}*x + {a * b}"),
        note=f"−{a} × −{b} = +{a * b}.",
    )


@template(id="alg.expand.double", skill="alg.expand.double",
          misconceptions=["m.expand.no_middle_terms"])
def expand_double(rng):
    p = rng.randint(1, 9)
    q = rng.randint(1, 9)
    return Item(
        stem=f"Expand and simplify  (x + {p})(x + {q})",
        correct=f"x² + {p + q}x + {p * q}",
        distractors={"m.expand.no_middle_terms": f"x² + {p * q}"},
        check=Check.equiv(f"(x + {p})*(x + {q})",
                          f"x**2 + {p + q}*x + {p * q}"),
        note="There are four products, and the two middle ones combine.",
    )


@template(id="alg.factorise.common", skill="alg.factorise.common",
          misconceptions=["m.factorise.partial_factor"])
def factorise_common(rng):
    # NOTE: the answer here is a FORM, not a value. 6(2x + 3) and 3(4x + 6)
    # are mathematically identical, so the options must be strings and are
    # compared as text. Check.equiv still verifies the correct form really
    # does equal the original expression.
    g = rng.choice([4, 6, 8, 9, 12])
    m = rng.randint(2, 5)
    n = rng.randint(2, 7)
    if sympy.igcd(m, n) != 1:
        m, n = 2, 3
    a, b = g * m, g * n
    # a proper divisor of g, so the distractor factorises incompletely
    partial = max(d for d in range(2, g) if g % d == 0)
    return Item(
        stem=f"Factorise fully  {a}x + {b}",
        correct=f"{g}({m}x + {n})",
        distractors={
            "m.factorise.partial_factor":
                f"{partial}({a // partial}x + {b // partial})",
        },
        check=Check.equiv(f"{a}*x + {b}", f"{g}*({m}*x + {n})"),
        note=f"The highest common factor of {a} and {b} is {g}, not {partial}.",
    )


@template(id="alg.factorise.quadratic", skill="alg.factorise.quadratic",
          misconceptions=["m.factorise.signs_swapped"])
def factorise_quadratic(rng):
    p = rng.randint(2, 8)
    q = rng.randint(1, 7)
    if p == q:
        q = p + 1
    # Answer is a FORM — compared as text, verified with Check.equiv.
    mid = p - q
    middle = f"+ {mid}x " if mid > 0 else (f"− {abs(mid)}x " if mid < 0 else "")
    return Item(
        stem=f"Factorise  x² {middle}− {p * q}".replace("  ", " "),
        correct=f"(x + {p})(x − {q})",
        distractors={
            "m.factorise.signs_swapped": f"(x − {p})(x + {q})",
        },
        check=Check.equiv(f"(x + {p})*(x - {q})",
                          f"x**2 + {p - q}*x - {p * q}"),
        note=f"Two numbers multiplying to −{p * q} and adding to {p - q}.",
    )


# ══════════════════════════════════════════════════════════════════════════
# ALGEBRA — equations, inequalities, sequences, graphs
# ══════════════════════════════════════════════════════════════════════════


@template(id="alg.eq.one_step_add", skill="alg.eq.one_step",
          misconceptions=["m.eq.same_operation_both_sides"])
def eq_one_step(rng):
    b = rng.randint(2, 15)
    x = rng.randint(2, 20)
    c = x + b
    return Item(
        stem=f"Solve  x + {b} = {c}",
        correct=x,
        distractors={"m.eq.same_operation_both_sides": c + b},
        check=Check.solve(f"x + {b} - {c}"),
        note=f"Subtract {b} from both sides.",
    )


@template(id="alg.eq.two_step", skill="alg.eq.two_step",
          misconceptions=["m.eq.wrong_inverse_order", "m.eq.sign_unchanged_on_move"])
def eq_two_step(rng):
    a = rng.choice([2, 3, 4, 5])
    b = a * rng.randint(1, 5)               # a | b keeps distractors whole
    x = rng.randint(2, 12)
    c = a * x + b
    return Item(
        stem=f"Solve  {a}x + {b} = {c}",
        correct=x,
        distractors={
            "m.eq.wrong_inverse_order": F(c, a) - b,
            "m.eq.sign_unchanged_on_move": F(c + b, a),
        },
        check=Check.solve(f"{a}*x + {b} - {c}"),
        note=f"Subtract {b} first, then divide by {a}.",
    )


@template(id="alg.quadratic.roots_from_factors", skill="alg.quadratic.solve_factorising",
          misconceptions=["m.quad.roots_keep_bracket_sign"])
def quadratic_roots(rng):
    p = rng.randint(1, 9)
    q = rng.randint(1, 9)
    if p == q:
        q = p + 1
    return Item(
        stem=f"Solve  (x + {p})(x − {q}) = 0",
        correct=f"x = −{p} or x = {q}",
        distractors={"m.quad.roots_keep_bracket_sign": f"x = {p} or x = −{q}"},
        check=Check.roots(f"(x + {p})*(x - {q})", [-p, q]),
        note="Each bracket is set to zero, which reverses the sign.",
    )


@template(id="alg.ineq.divide_negative", skill="alg.ineq.solve_linear",
          misconceptions=["m.ineq.no_flip_on_negative"])
def ineq_negative(rng):
    a = rng.randint(2, 7)
    k = a * rng.randint(2, 8)
    return Item(
        stem=f"Solve  −{a}x > {k}",
        correct=f"x < −{k // a}",
        distractors={"m.ineq.no_flip_on_negative": f"x > −{k // a}"},
        check=Check.none("inequality direction; the boundary is checked by "
                         "construction and the direction is the item's point"),
        note=f"Dividing by −{a} reverses the inequality sign.",
    )


@template(id="alg.seq.nth_term", skill="alg.seq.nth_term_linear",
          misconceptions=["m.nth.constant_is_first_term", "m.nth.difference_only"])
def nth_term(rng):
    d = rng.randint(2, 9)
    first = rng.randint(1, 12)
    terms = [first + d * i for i in range(4)]
    const = first - d
    if const == 0:
        const = 1
        first = d + 1
        terms = [first + d * i for i in range(4)]
    return Item(
        stem=f"Find the nth term of  {', '.join(map(str, terms))}, ...",
        correct=f"{d}n + {const}" if const > 0 else f"{d}n − {abs(const)}",
        distractors={
            "m.nth.constant_is_first_term":
                f"{d}n + {first}" if first > 0 else f"{d}n − {abs(first)}",
            "m.nth.difference_only": f"{d}n",
        },
        check=Check.sequence(f"{d}*n + {const}", terms),
        note=f"The difference is {d}, so start from {d}n and adjust by {const}.",
    )


@template(id="alg.graph.gradient_positive", skill="alg.graph.gradient",
          misconceptions=["m.gradient.run_over_rise"])
def gradient_positive(rng):
    x1 = rng.randint(0, 4)
    run = rng.randint(2, 5)
    m = rng.randint(2, 6)
    x2 = x1 + run
    y1 = rng.randint(0, 6)
    y2 = y1 + m * run
    return Item(
        stem=f"A line passes through ({x1}, {y1}) and ({x2}, {y2}). "
             f"Find its gradient.",
        correct=F(y2 - y1, x2 - x1),
        distractors={"m.gradient.run_over_rise": F(x2 - x1, y2 - y1)},
        check=Check.eval(f"({y2} - {y1})/({x2} - {x1})"),
        note="Gradient is the change in y divided by the change in x.",
    )


@template(id="alg.graph.gradient_negative", skill="alg.graph.gradient",
          misconceptions=["m.gradient.sign_ignored"])
def gradient_negative(rng):
    x1 = rng.randint(0, 4)
    run = rng.randint(2, 5)
    m = rng.randint(2, 6)
    x2 = x1 + run
    y1 = rng.randint(20, 30)
    y2 = y1 - m * run
    return Item(
        stem=f"A line passes through ({x1}, {y1}) and ({x2}, {y2}). "
             f"Find its gradient.",
        correct=F(y2 - y1, x2 - x1),
        distractors={"m.gradient.sign_ignored": F(abs(y2 - y1), x2 - x1)},
        check=Check.eval(f"({y2} - {y1})/({x2} - {x1})"),
        note="The line slopes downwards, so the gradient is negative.",
    )


# ══════════════════════════════════════════════════════════════════════════
# RATIO AND PROPORTION
# ══════════════════════════════════════════════════════════════════════════


@template(id="ratio.share.larger_part", skill="ratio.share",
          misconceptions=["m.ratio.divides_by_one_part", "m.ratio.shares_equally"])
def ratio_share(rng):
    # The ratio must be in its simplest form — a paper would never print 4:8.
    for _ in range(40):
        a = rng.randint(1, 5)
        b = a + rng.randint(1, 5)
        if sympy.igcd(a, b) == 1:
            break
    total = (a + b) * rng.randint(4, 15) * 2
    return Item(
        stem=f"£{total} is shared in the ratio {a} : {b}. "
             f"How much is the larger share?",
        correct=F(total * b, a + b),
        distractors={
            "m.ratio.divides_by_one_part": F(total, b),
            "m.ratio.shares_equally": F(total, 2),
        },
        check=Check.eval(f"{total}*{b}/({a} + {b})"),
        note=f"There are {a + b} parts in total.",
        fmt="money",
    )


@template(id="ratio.pct.increase", skill="ratio.pct.increase_decrease",
          misconceptions=["m.pct.change_forgets_original"])
def pct_increase(rng):
    pct = rng.choice([5, 10, 15, 20, 25])
    amount = pct * rng.randint(4, 15)
    change = F(pct * amount, 100)
    return Item(
        stem=f"Increase {amount} by {pct}%",
        correct=amount + change,
        distractors={"m.pct.change_forgets_original": change},
        check=Check.eval(f"{amount}*(100 + {pct})/100"),
        note="The question asks for the new amount, not the increase.",
    )


@template(id="ratio.pct.reverse", skill="ratio.pct.reverse",
          misconceptions=["m.pct.reverse_applied_forwards"])
def pct_reverse(rng):
    pct = rng.choice([10, 20, 25, 50])
    original = rng.randint(2, 20) * 20
    new = F(original * (100 + pct), 100)
    return Item(
        stem=f"After a {pct}% increase, a price is £{new}. "
             f"What was the original price?",
        correct=original,
        distractors={
            "m.pct.reverse_applied_forwards": F(new * (100 - pct), 100),
        },
        check=Check.solve(f"x*(100 + {pct})/100 - {new}"),
        note=f"Divide by {F(100 + pct, 100)}, do not subtract {pct}%.",
        fmt="money",
    )


@template(id="ratio.compound_interest", skill="ratio.compound_interest",
          misconceptions=["m.interest.simple_for_compound"])
def compound_interest(rng):
    principal = rng.choice([200, 400, 500, 800, 1000])
    rate = rng.choice([5, 10, 20])
    years = rng.choice([2, 3])
    mult = F(100 + rate, 100)
    return Item(
        stem=f"£{principal} is invested at {rate}% compound interest per year. "
             f"What is it worth after {years} years?",
        correct=principal * mult ** years,
        distractors={
            "m.interest.simple_for_compound":
                principal + principal * F(rate, 100) * years,
        },
        check=Check.eval(f"{principal}*((100 + {rate})/100)**{years}"),
        note="Each year's interest is calculated on the new total.",
        fmt="money",
    )


@template(id="ratio.speed", skill="ratio.compound_units",
          misconceptions=["m.speed.formula_inverted"])
def speed(rng):
    time = rng.randint(2, 8)
    sp = rng.choice([30, 40, 45, 50, 60, 70])
    dist = sp * time
    return Item(
        stem=f"A car travels {dist} km in {time} hours. Find its average speed.",
        correct=sp,
        distractors={"m.speed.formula_inverted": F(time, dist)},
        check=Check.eval(f"{dist}/{time}"),
        note="Speed is distance divided by time.",
    )


# ══════════════════════════════════════════════════════════════════════════
# GEOMETRY
# ══════════════════════════════════════════════════════════════════════════


@template(id="geo.angles.third_angle", skill="geo.angles.triangle",
          misconceptions=["m.angle.triangle_sums_360"])
def third_angle(rng):
    a = rng.randint(30, 80)
    b = rng.randint(30, 80)
    return Item(
        stem=f"Two angles in a triangle are {a}° and {b}°. Find the third angle.",
        correct=180 - a - b,
        distractors={"m.angle.triangle_sums_360": 360 - a - b},
        check=Check.eval(f"180 - {a} - {b}"),
        note="Angles in a triangle add up to 180°.",
    )


@template(id="geo.polygon.interior_sum", skill="geo.polygon.interior",
          misconceptions=["m.polygon.interior_uses_n"])
def interior_sum(rng):
    n = rng.randint(5, 12)
    return Item(
        stem=f"Find the sum of the interior angles of a polygon with {n} sides",
        correct=(n - 2) * 180,
        distractors={"m.polygon.interior_uses_n": n * 180},
        check=Check.eval(f"({n} - 2)*180"),
        note=f"The polygon splits into {n - 2} triangles.",
    )


@template(id="geo.area.triangle", skill="geo.area.triangle",
          misconceptions=["m.area.triangle_forgets_half"])
def area_triangle(rng):
    base = rng.randint(3, 20)
    height = rng.randint(3, 20)
    if (base * height) % 2:
        base += 1
    return Item(
        stem=f"Find the area of a triangle with base {base} cm and "
             f"perpendicular height {height} cm",
        correct=F(base * height, 2),
        distractors={"m.area.triangle_forgets_half": base * height},
        check=Check.eval(f"{base}*{height}/2"),
        note="A triangle is half of the surrounding rectangle.",
    )


@template(id="geo.area.trapezium", skill="geo.area.trapezium",
          misconceptions=["m.area.trapezium_forgets_half"])
def area_trapezium(rng):
    a = rng.randint(3, 12)
    b = a + rng.randint(1, 10)
    h = rng.choice([4, 6, 8, 10])
    return Item(
        stem=f"Find the area of a trapezium with parallel sides {a} cm and "
             f"{b} cm, and height {h} cm",
        correct=F((a + b) * h, 2),
        distractors={"m.area.trapezium_forgets_half": (a + b) * h},
        check=Check.eval(f"({a} + {b})*{h}/2"),
        note="Average the parallel sides, then multiply by the height.",
    )


@template(id="geo.circle.area", skill="geo.circle.area",
          misconceptions=["m.circle.area_uses_diameter",
                          "m.circle.area_formula_is_circumference"])
def circle_area(rng):
    r = rng.randint(2, 12)
    return Item(
        stem=f"A circle has radius {r} cm. Find its area, in terms of π.",
        correct=PI * r ** 2,
        distractors={
            "m.circle.area_uses_diameter": PI * (2 * r) ** 2,
            "m.circle.area_formula_is_circumference": 2 * PI * r,
        },
        check=Check.eval(f"pi*{r}**2"),
        note="Area is πr², using the radius.",
    )


@template(id="geo.circle.circumference", skill="geo.circle.circumference",
          misconceptions=["m.circle.circumference_uses_radius"])
def circle_circumference(rng):
    r = rng.randint(2, 12)
    d = 2 * r
    return Item(
        stem=f"A circle has diameter {d} cm. Find its circumference, "
             f"in terms of π.",
        correct=PI * d,
        distractors={"m.circle.circumference_uses_radius": PI * r},
        check=Check.eval(f"pi*{d}"),
        note="Circumference is πd, and the diameter is given.",
    )


@template(id="geo.pythagoras.shorter_side", skill="geo.pythagoras.shorter_side",
          misconceptions=["m.pythag.always_adds"])
def pythagoras_shorter(rng):
    a, b, c = rng.choice([(3, 4, 5), (6, 8, 10), (5, 12, 13),
                          (9, 12, 15), (8, 15, 17), (7, 24, 25)])
    return Item(
        stem=f"A right-angled triangle has hypotenuse {c} cm and one shorter "
             f"side {a} cm. Find the other shorter side.",
        correct=b,
        distractors={"m.pythag.always_adds": sympy.sqrt(c ** 2 + a ** 2)},
        check=Check.eval(f"sqrt({c}**2 - {a}**2)"),
        note="To find a shorter side, subtract the squares.",
    )


@template(id="geo.volume.triangular_prism", skill="geo.volume.prism",
          misconceptions=["m.prism.volume_is_perimeter_times_length"])
def volume_prism(rng):
    a, b, c = rng.choice([(9, 12, 15), (8, 15, 17), (7, 24, 25), (20, 21, 29)])
    length = rng.randint(3, 15)
    area = F(a * b, 2)
    perim = a + b + c
    return Item(
        stem=f"A prism has a right-angled triangular cross-section with "
             f"shorter sides {a} cm and {b} cm, and length {length} cm. "
             f"Find its volume.",
        correct=area * length,
        distractors={
            "m.prism.volume_is_perimeter_times_length": perim * length,
        },
        check=Check.eval(f"({a}*{b}/2)*{length}"),
        note="Volume is the cross-sectional area times the length.",
    )


# ══════════════════════════════════════════════════════════════════════════
# PROBABILITY
# ══════════════════════════════════════════════════════════════════════════


@template(id="prob.independent_both", skill="prob.tree_diagrams",
          misconceptions=["m.prob.adds_independent_events"])
def independent_both(rng):
    d1 = rng.choice([2, 3, 4, 5])
    d2 = rng.choice([2, 3, 4, 6])
    return Item(
        stem=f"The probability it rains is 1/{d1}. The probability a bus is "
             f"late is 1/{d2}. The events are independent. Find the "
             f"probability that both happen.",
        correct=F(1, d1 * d2),
        distractors={"m.prob.adds_independent_events": F(1, d1) + F(1, d2)},
        check=Check.eval(f"(1/{d1})*(1/{d2})"),
        note="For both events, multiply the probabilities.",
    )


@template(id="prob.expected_outcomes", skill="prob.expected_outcomes",
          misconceptions=["m.prob.expected_uses_count"])
def expected_outcomes(rng):
    faces = rng.choice([4, 5, 6, 8, 10])
    trials = faces * rng.randint(5, 20)
    return Item(
        stem=f"A fair {faces}-sided dice is rolled {trials} times. "
             f"How many times would you expect to roll a 1?",
        correct=F(trials, faces),
        distractors={"m.prob.expected_uses_count": faces},
        check=Check.eval(f"{trials}*(1/{faces})"),
        note=f"Multiply the number of rolls by 1/{faces}.",
    )


# ══════════════════════════════════════════════════════════════════════════
# STATISTICS
# ══════════════════════════════════════════════════════════════════════════


@template(id="stats.mean.list", skill="stats.mean",
          misconceptions=["m.mean.divides_by_wrong_count"])
def mean_list(rng):
    n = rng.randint(5, 7)
    data = [rng.randint(1, 30) for _ in range(n)]
    total = sum(data)
    return Item(
        stem=f"Find the mean of  {', '.join(map(str, data))}",
        correct=F(total, n),
        distractors={"m.mean.divides_by_wrong_count": F(total, n - 1)},
        check=Check.stat("mean", data),
        note=f"Divide the total by {n}, the number of values.",
    )


@template(id="stats.median.unsorted_odd", skill="stats.median",
          misconceptions=["m.median.no_sort"])
def median_unsorted(rng):
    # Resample so the unsorted middle differs from the true median,
    # otherwise the distractor collides and the instance is wasted.
    for _ in range(40):
        data = rng.sample(range(1, 40), 5)
        if data[2] != sorted(data)[2]:
            break
    mid_unsorted = data[2]
    return Item(
        stem=f"Find the median of  {', '.join(map(str, data))}",
        correct=sorted(data)[2],
        distractors={"m.median.no_sort": mid_unsorted},
        check=Check.stat("median", data),
        note="Put the values in order first.",
    )


@template(id="stats.median.even_count", skill="stats.median",
          misconceptions=["m.median.even_takes_lower"])
def median_even(rng):
    data = sorted(rng.sample(range(1, 40), 6))
    lo, hi = data[2], data[3]
    if (lo + hi) % 2 == 0:
        hi += 1
        data[3] = hi
        data = sorted(data)
        lo, hi = data[2], data[3]
    return Item(
        stem=f"Find the median of  {', '.join(map(str, data))}",
        correct=F(lo + hi, 2),
        distractors={"m.median.even_takes_lower": lo},
        check=Check.stat("median", data),
        note="With six values, the median is the mean of the middle two.",
    )


@template(id="stats.range.list", skill="stats.range",
          misconceptions=["m.range.adds_extremes"])
def range_list(rng):
    data = rng.sample(range(1, 50), rng.randint(4, 7))
    return Item(
        stem=f"Find the range of  {', '.join(map(str, data))}",
        correct=max(data) - min(data),
        distractors={"m.range.adds_extremes": max(data) + min(data)},
        check=Check.stat("range", data),
        note="Range is the largest value minus the smallest.",
    )


@template(id="stats.mean.frequency_table", skill="stats.mean.frequency_table",
          misconceptions=["m.freq_mean.divides_by_rows", "m.freq_mean.ignores_frequency"])
def mean_frequency(rng):
    values = sorted(rng.sample(range(0, 8), 4))
    freqs = [rng.randint(2, 9) for _ in values]
    total_f = sum(freqs)
    total_fx = sum(v * f for v, f in zip(values, freqs))
    rows = " ".join(f"{v}×{f}" for v, f in zip(values, freqs))
    return Item(
        stem=f"A survey records these values and frequencies:  {rows}.  "
             f"Find the mean.",
        correct=F(total_fx, total_f),
        distractors={
            "m.freq_mean.divides_by_rows": F(total_fx, len(values)),
            "m.freq_mean.ignores_frequency": F(sum(values), len(values)),
        },
        check=Check.eval(
            "(" + "+".join(f"{v}*{f}" for v, f in zip(values, freqs)) + ")"
            f"/{total_f}"
        ),
        note=f"Divide the total of value × frequency by {total_f}.",
    )


@template(id="num.std_form.write", skill="num.standard_form",
          misconceptions=["m.std_form.mantissa_not_normalised"])
def std_form_write(rng):
    # Form-valued answer. 4.62×10³ and 46.2×10² are the SAME number, so this
    # item cannot be verified numerically — both options would pass. What
    # makes one correct is that its mantissa is normalised to 1 <= m < 10,
    # which the parameter choice enforces structurally (d1 >= 1).
    d1 = rng.randint(1, 9)
    d2 = rng.randint(0, 9)
    d3 = rng.randint(1, 9)
    p = rng.randint(3, 6)
    value = (d1 * 100 + d2 * 10 + d3) * 10 ** (p - 2)   # always an integer
    assert 1 <= d1 <= 9, "mantissa must be normalised"
    return Item(
        stem=f"Write {value} in standard form",
        correct=f"{d1}.{d2}{d3} × 10^{p}",
        distractors={
            "m.std_form.mantissa_not_normalised": f"{d1}{d2}.{d3} × 10^{p - 1}",
        },
        check=Check.none(
            "both options are numerically equal; correctness is whether the "
            "mantissa is normalised to 1 <= m < 10, enforced by construction"
        ),
        note="In standard form the first number must be at least 1 and less than 10.",
    )
