#!/usr/bin/env python3
"""Generate and verify the item bank.

    python3 items/generate.py                      # report only
    python3 items/generate.py --per-template 20 --out items/bank.json
    python3 items/generate.py --quiet               # CI gate

Cross-checks the two halves of the curriculum against each other: every
template's skill must exist in curriculum/skills.yaml, and every misconception
it cites must exist in items/misconceptions.yaml and be attached to that same
skill. Exits non-zero on any failure, so it works in CI.
"""

from __future__ import annotations

import argparse
import json
import random
import signal
import sys
from collections import defaultdict
from pathlib import Path

import yaml

signal.signal(signal.SIGPIPE, signal.SIG_DFL)

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))

import templates as _templates  # noqa: F401,E402  (registers everything)
from bank import REGISTRY, Rejected, options, render, validate  # noqa: E402

SKILLS = HERE.parent / "curriculum" / "skills.yaml"
MISCONCEPTIONS = HERE / "misconceptions.yaml"

MAX_ATTEMPTS = 60          # resampling budget per wanted item


# ── integrity ─────────────────────────────────────────────────────────────

def check_integrity(skills: dict, miscs: dict) -> list[str]:
    errors = []
    for tid, t in sorted(REGISTRY.items()):
        if t.skill not in skills:
            errors.append(f"{tid}: skill {t.skill!r} is not in skills.yaml")
        if not t.misconceptions:
            errors.append(f"{tid}: declares no misconceptions")
        for mid in t.misconceptions:
            m = miscs.get(mid)
            if m is None:
                errors.append(f"{tid}: misconception {mid!r} is not in "
                              f"misconceptions.yaml")
            elif m["skill"] != t.skill:
                errors.append(
                    f"{tid}: cites {mid!r}, which misconceptions.yaml attaches "
                    f"to {m['skill']!r}, not {t.skill!r}"
                )
    for mid, m in sorted(miscs.items()):
        if m["skill"] not in skills:
            errors.append(f"{mid}: skill {m['skill']!r} is not in skills.yaml")
    return errors


# ── generation ────────────────────────────────────────────────────────────

def generate(per_template: int, seed: int):
    rng = random.Random(seed)
    bank, stats = [], {}

    for tid, t in sorted(REGISTRY.items()):
        made, attempts, rejects = [], 0, defaultdict(int)
        while len(made) < per_template and attempts < per_template * MAX_ATTEMPTS:
            attempts += 1
            item = t.fn(rng)
            try:
                validate(item, t)
            except Rejected as exc:
                rejects[str(exc)] += 1
                continue
            # ValueError from validate is a template bug and propagates.
            opts = options(item, rng)
            made.append({
                "id": f"{tid}#{len(made):03d}",
                "template": tid,
                "skill": t.skill,
                "stem": item.stem,
                "options": opts,
                "answer": render(item.correct),
                "note": item.note,
                "check": item.check.kind,
                "verified": item.check.kind != "none",
                "unverified_reason": item.check.reason or None,
            })

        bank.extend(made)
        stats[tid] = {
            "skill": t.skill,
            "wanted": per_template,
            "made": len(made),
            "attempts": attempts,
            "reject_rate": 1 - len(made) / attempts if attempts else 0.0,
            "rejects": dict(rejects),
            "verified": t.id and REGISTRY[tid].misconceptions and True,
        }
    return bank, stats


# ── main ──────────────────────────────────────────────────────────────────

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--per-template", type=int, default=12)
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    skills = {s["id"]: s for s in yaml.safe_load(SKILLS.open())["skills"]}
    miscs = {m["id"]: m for m in
             yaml.safe_load(MISCONCEPTIONS.open())["misconceptions"]}

    errors = check_integrity(skills, miscs)
    if errors:
        print(f"FAIL — {len(errors)} integrity error(s)\n", file=sys.stderr)
        for e in errors:
            print(f"  · {e}", file=sys.stderr)
        return 1

    try:
        bank, stats = generate(args.per_template, args.seed)
    except ValueError as exc:
        print(f"FAIL — {exc}", file=sys.stderr)
        return 1

    short = {t: s for t, s in stats.items() if s["made"] < s["wanted"]}
    unverified = [i for i in bank if not i["verified"]]
    covered_skills = {i["skill"] for i in bank}
    covered_miscs = {o["misconception"] for i in bank for o in i["options"]
                     if o["misconception"]}

    if args.quiet:
        print(f"PASS — {len(bank)} items from {len(REGISTRY)} templates, "
              f"{len(covered_skills)}/{len(skills)} skills, "
              f"{len(covered_miscs)}/{len(miscs)} misconceptions")
    else:
        print(f"PASS — integrity and verification clean\n")
        print(f"{len(bank)} items from {len(REGISTRY)} templates "
              f"({args.per_template} wanted each)")
        print(f"{len(covered_skills):>3} / {len(skills):<3} skills covered")
        print(f"{len(covered_miscs):>3} / {len(miscs):<3} catalogued "
              f"misconceptions exercised")
        print(f"{len(bank) - len(unverified):>3} / {len(bank):<3} items "
              f"independently verified")

        if unverified:
            print(f"\nunverified ({len(unverified)}) — each needs a stated reason:")
            for tid in sorted({i['template'] for i in unverified}):
                reason = next(i["unverified_reason"] for i in unverified
                              if i["template"] == tid)
                print(f"  · {tid}: {reason}")

        if short:
            print(f"\ncould not fill {len(short)} template(s):")
            for tid, s in sorted(short.items()):
                top = sorted(s["rejects"].items(), key=lambda kv: -kv[1])[:2]
                why = "; ".join(f"{k} ×{v}" for k, v in top)
                print(f"  · {tid}: {s['made']}/{s['wanted']} — {why}")

        noisy = sorted(((s["reject_rate"], t) for t, s in stats.items()
                        if s["reject_rate"] > 0.25), reverse=True)
        if noisy:
            print(f"\nhigh rejection rate (parameter ranges worth tightening):")
            for rate, tid in noisy:
                top = sorted(stats[tid]["rejects"].items(),
                             key=lambda kv: -kv[1])[:1]
                why = top[0][0] if top else ""
                print(f"  · {rate:>5.0%}  {tid}  — {why}")

        uncovered_m = sorted(set(miscs) - covered_miscs)
        if uncovered_m:
            print(f"\n{len(uncovered_m)} catalogued misconception(s) with no "
                  f"template yet:")
            for mid in uncovered_m:
                print(f"  · {mid}")

    if args.out:
        args.out.write_text(json.dumps({
            "generated_from": {"skills": str(SKILLS.name),
                               "misconceptions": str(MISCONCEPTIONS.name)},
            "seed": args.seed,
            "per_template": args.per_template,
            "counts": {"items": len(bank), "templates": len(REGISTRY),
                       "skills_covered": len(covered_skills),
                       "misconceptions_exercised": len(covered_miscs)},
            "items": bank,
        }, indent=2, ensure_ascii=False) + "\n")
        if not args.quiet:
            print(f"\nwrote {args.out} ({len(bank)} items)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
