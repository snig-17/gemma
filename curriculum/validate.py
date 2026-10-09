#!/usr/bin/env python3
"""Validate and report on the GCSE skill graph.

Enforces the invariants in docs/DESIGN.md §3.1 and prints the structural
report you need before trusting the graph: depth layering, diagnostic
leverage, and spec_ref coverage.

    python3 curriculum/validate.py [--json]

Exits non-zero if any invariant fails, so it works as a CI gate.
Standard library plus PyYAML only — no graph library, by design.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict, deque
from pathlib import Path

import yaml

MAX_PREREQS = 4
DOMAINS = {"number", "algebra", "ratio", "geometry", "probability", "statistics"}
KEY_STAGES = {"KS2", "KS3", "KS4"}
TIERS = {"foundation", "higher"}
PRIOR_STAGES = {"KS2", "KS3"}

DEFAULT_PATH = Path(__file__).parent / "skills.yaml"


# ── loading ───────────────────────────────────────────────────────────────

def load(path: Path) -> list[dict]:
    with path.open() as fh:
        doc = yaml.safe_load(fh)
    if not isinstance(doc, dict) or "skills" not in doc:
        raise SystemExit(f"{path}: expected a top-level 'skills:' key")
    skills = doc["skills"]
    if not isinstance(skills, list) or not skills:
        raise SystemExit(f"{path}: 'skills' must be a non-empty list")
    return skills


# ── invariants ────────────────────────────────────────────────────────────

def check_fields(skills: list[dict]) -> list[str]:
    """Every node is well-formed and ids are unique."""
    errors: list[str] = []
    seen: set[str] = set()
    required = {"id", "title", "domain", "key_stage", "tier", "spec_ref", "prereqs"}

    for i, s in enumerate(skills):
        where = s.get("id") or f"index {i}"
        missing = required - s.keys()
        if missing:
            errors.append(f"{where}: missing field(s) {sorted(missing)}")
            continue
        if s["id"] in seen:
            errors.append(f"{s['id']}: duplicate id")
        seen.add(s["id"])
        if s["domain"] not in DOMAINS:
            errors.append(f"{s['id']}: unknown domain {s['domain']!r}")
        if s["key_stage"] not in KEY_STAGES:
            errors.append(f"{s['id']}: unknown key_stage {s['key_stage']!r}")
        if s["tier"] not in TIERS:
            errors.append(f"{s['id']}: unknown tier {s['tier']!r}")
        if not isinstance(s["prereqs"], list):
            errors.append(f"{s['id']}: prereqs must be a list")
        if s["key_stage"] == "KS4" and s["spec_ref"] is None:
            errors.append(f"{s['id']}: KS4 skill must carry a spec_ref")
        # A KS2/KS3 skill MAY carry a spec_ref: the GCSE spec restates plenty
        # of primary content (R1 time conversion, G16 area of a rectangle,
        # S2 frequency tables). That is reported, not an error — those skills
        # are assessed at GCSE despite being taught years earlier, which is
        # exactly the `foundation` coverage bucket in DESIGN.md §3.2.
    return errors


def check_edges(skills: list[dict], index: dict[str, dict]) -> list[str]:
    """No dangling references, no self-edges, and the fan-in cap holds."""
    errors: list[str] = []
    for s in skills:
        prereqs = s.get("prereqs") or []
        if len(prereqs) > MAX_PREREQS:
            errors.append(
                f"{s['id']}: {len(prereqs)} prerequisites exceeds the cap of "
                f"{MAX_PREREQS} — the skill is probably not atomic"
            )
        if len(set(prereqs)) != len(prereqs):
            errors.append(f"{s['id']}: duplicate entries in prereqs")
        for p in prereqs:
            if p == s["id"]:
                errors.append(f"{s['id']}: depends on itself")
            elif p not in index:
                errors.append(f"{s['id']}: prereq {p!r} does not exist")
    return errors


def find_cycles(skills: list[dict], index: dict[str, dict]) -> tuple[list[str], list[str]]:
    """Kahn's algorithm. Returns (errors, topological_order)."""
    indeg = {s["id"]: 0 for s in skills}
    dependents: dict[str, list[str]] = defaultdict(list)

    for s in skills:
        for p in s.get("prereqs") or []:
            if p in index:
                indeg[s["id"]] += 1
                dependents[p].append(s["id"])

    queue = deque(sorted(sid for sid, d in indeg.items() if d == 0))
    order: list[str] = []
    while queue:
        sid = queue.popleft()
        order.append(sid)
        for dep in dependents[sid]:
            indeg[dep] -= 1
            if indeg[dep] == 0:
                queue.append(dep)

    if len(order) != len(skills):
        stuck = sorted(set(indeg) - set(order))
        return (
            [f"graph contains a cycle; {len(stuck)} node(s) unresolved: "
             f"{', '.join(stuck[:10])}{' …' if len(stuck) > 10 else ''}"],
            order,
        )
    return [], order


def check_reachability(skills: list[dict], index: dict[str, dict]) -> list[str]:
    """Every KS4 skill must trace back to assumed prior knowledge."""
    errors: list[str] = []
    for s in skills:
        if s["key_stage"] != "KS4":
            continue
        seen: set[str] = set()
        stack = list(s.get("prereqs") or [])
        grounded = False
        while stack:
            cur = stack.pop()
            if cur in seen or cur not in index:
                continue
            seen.add(cur)
            if index[cur]["key_stage"] in PRIOR_STAGES:
                grounded = True
                break
            stack.extend(index[cur].get("prereqs") or [])
        if not grounded:
            errors.append(
                f"{s['id']}: KS4 skill does not reach any KS2/KS3 prerequisite "
                f"— the diagnostic cannot ground it"
            )
    return errors


def check_tier_consistency(skills: list[dict], index: dict[str, dict]) -> list[str]:
    """Foundation content is a subset of Higher, so a Foundation skill can
    never require a Higher-only one."""
    errors = []
    for s in skills:
        if s["tier"] != "foundation":
            continue
        for p in s.get("prereqs") or []:
            if p in index and index[p]["tier"] == "higher":
                errors.append(
                    f"{s['id']} (foundation): depends on higher-only skill {p}"
                )
    return errors


# ── structural report ─────────────────────────────────────────────────────

def ancestors(sid: str, index: dict[str, dict]) -> set[str]:
    """All transitive prerequisites."""
    seen: set[str] = set()
    stack = list(index[sid].get("prereqs") or [])
    while stack:
        cur = stack.pop()
        if cur in seen or cur not in index:
            continue
        seen.add(cur)
        stack.extend(index[cur].get("prereqs") or [])
    return seen


def depths(order: list[str], index: dict[str, dict]) -> dict[str, int]:
    """Longest path from a root. Relies on topological order."""
    depth = {sid: 0 for sid in index}
    for sid in order:
        for p in index[sid].get("prereqs") or []:
            if p in index:
                depth[sid] = max(depth[sid], depth[p] + 1)
    return depth


def build_report(skills: list[dict], index: dict[str, dict], order: list[str]) -> dict:
    anc = {sid: ancestors(sid, index) for sid in index}
    desc: dict[str, set[str]] = defaultdict(set)
    for sid, a in anc.items():
        for p in a:
            desc[p].add(sid)

    depth = depths(order, index) if order else {}

    by_domain = defaultdict(int)
    by_stage = defaultdict(int)
    by_tier = defaultdict(int)
    by_spec = defaultdict(list)
    for s in skills:
        by_domain[s["domain"]] += 1
        by_stage[s["key_stage"]] += 1
        by_tier[s["tier"]] += 1
        if s["spec_ref"]:
            by_spec[s["spec_ref"]].append(s["id"])

    roots = [s["id"] for s in skills if not (s.get("prereqs") or [])]
    leaves = [s["id"] for s in skills if not desc[s["id"]]]

    # Taught pre-KS4 but still assessed at GCSE. These are the `foundation`
    # coverage bucket (DESIGN.md §3.2): always in scope, and where the
    # diagnostic is most likely to find the real damage.
    early_assessed = [
        s["id"] for s in skills
        if s["key_stage"] in PRIOR_STAGES and s["spec_ref"]
    ]

    # §3.4: the diagnostic picks items by graph leverage. A node with many
    # ancestors and descendants resolves the most uncertainty per item.
    leverage = sorted(
        ((len(anc[s]) + len(desc[s]), s) for s in index),
        reverse=True,
    )

    return {
        "total": len(skills),
        "by_domain": dict(sorted(by_domain.items())),
        "by_key_stage": dict(sorted(by_stage.items())),
        "by_tier": dict(sorted(by_tier.items())),
        "roots": sorted(roots),
        "leaves": sorted(leaves),
        "early_assessed": sorted(early_assessed),
        "max_depth": max(depth.values()) if depth else 0,
        "depth_histogram": {
            str(d): sum(1 for v in depth.values() if v == d)
            for d in range(max(depth.values()) + 1)
        } if depth else {},
        "spec_refs_used": len(by_spec),
        "spec_ref_skill_counts": {k: len(v) for k, v in sorted(by_spec.items())},
        "top_leverage": [{"id": s, "reach": n} for n, s in leverage[:15]],
        "deepest": sorted(
            ({"id": s, "depth": d} for s, d in depth.items()),
            key=lambda r: -r["depth"],
        )[:10] if depth else [],
    }


def print_report(r: dict) -> None:
    print(f"\n{r['total']} skills\n")

    print("by domain")
    for k, v in r["by_domain"].items():
        print(f"  {k:<12} {v:>4}")
    print("\nby key stage          by tier")
    stages = list(r["by_key_stage"].items())
    tiers = list(r["by_tier"].items())
    for i in range(max(len(stages), len(tiers))):
        left = f"  {stages[i][0]:<8} {stages[i][1]:>4}" if i < len(stages) else " " * 15
        right = f"  {tiers[i][0]:<12} {tiers[i][1]:>4}" if i < len(tiers) else ""
        print(f"{left:<22}{right}")

    print(f"\n{len(r['roots'])} roots (no prerequisites), "
          f"{len(r['leaves'])} leaves (nothing depends on them)")
    print(f"max depth {r['max_depth']}")
    print("\ndepth histogram")
    for d, n in r["depth_histogram"].items():
        print(f"  {d:>2} {'█' * n} {n}")

    print(f"\n{r['spec_refs_used']} distinct DfE spec refs cited "
          f"(ALL UNVERIFIED — see README)")
    print(f"{len(r['early_assessed'])} skills taught pre-KS4 but still assessed "
          f"at GCSE\n  (the `foundation` bucket — always in scope)")

    print("\nhighest diagnostic leverage (ancestors + descendants)")
    print("these are the items the adaptive diagnostic should reach for first")
    for row in r["top_leverage"]:
        print(f"  {row['reach']:>4}  {row['id']}")


# ── main ──────────────────────────────────────────────────────────────────

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", nargs="?", type=Path, default=DEFAULT_PATH)
    ap.add_argument("--json", action="store_true", help="emit the report as JSON")
    ap.add_argument("--quiet", action="store_true", help="invariants only")
    args = ap.parse_args()

    skills = load(args.path)
    index = {s["id"]: s for s in skills if "id" in s}

    errors: list[str] = []
    errors += check_fields(skills)
    errors += check_edges(skills, index)

    cycle_errors, order = find_cycles(skills, index)
    errors += cycle_errors

    if not cycle_errors:
        errors += check_reachability(skills, index)
        errors += check_tier_consistency(skills, index)

    if errors:
        print(f"FAIL — {len(errors)} invariant violation(s)\n", file=sys.stderr)
        for e in errors:
            print(f"  · {e}", file=sys.stderr)
        return 1

    report = build_report(skills, index, order)
    if args.json:
        print(json.dumps(report, indent=2))
    elif not args.quiet:
        print(f"PASS — all invariants hold ({args.path})")
        print_report(report)
    else:
        print(f"PASS — {report['total']} skills, all invariants hold")
    return 0


if __name__ == "__main__":
    sys.exit(main())
