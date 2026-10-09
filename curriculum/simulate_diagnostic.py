#!/usr/bin/env python3
"""Simulate the adaptive diagnostic against the real skill graph.

docs/DESIGN.md §3.4 claims ~25 items can locate a student across the graph.
That was an estimate from graph structure, not a measurement. This measures it.

    python3 curriculum/simulate_diagnostic.py
    python3 curriculum/simulate_diagnostic.py --students 500 --budget 40

Synthetic students are generated top-down through the graph so mastery has a
realistic frontier shape: you do not master a skill whose prerequisites you
have not mastered. The diagnostic then tries to recover that frontier.

Judged on BALANCED accuracy (mean of sensitivity and specificity). Raw
accuracy is badly inflated here — deep skills are mastered by almost nobody,
so "predict not mastered" scores ~92% on them for free.

Standard library plus PyYAML only.
"""

from __future__ import annotations

import argparse
import math
import random
import statistics
from collections import defaultdict, deque
from pathlib import Path

import yaml

DEFAULT_PATH = Path(__file__).parent / "skills.yaml"

# item response model for 4-option diagnostic multiple choice
P_CORRECT_IF_MASTERED = 0.90      # 1 - slip
P_CORRECT_IF_NOT = 0.22           # guess, slightly below 1/4

GAMMA = 0.55                      # distance decay for belief propagation
P_HIGH, P_LOW = 0.95, 0.06        # belief set on the skill just asked


# ── graph ─────────────────────────────────────────────────────────────────

def load_graph(path: Path):
    skills = yaml.safe_load(path.open())["skills"]
    index = {s["id"]: s for s in skills}
    prereqs = {s["id"]: [p for p in (s["prereqs"] or []) if p in index] for s in skills}

    indeg = {k: len(v) for k, v in prereqs.items()}
    dependents = defaultdict(list)
    for sid, ps in prereqs.items():
        for p in ps:
            dependents[p].append(sid)

    order: list[str] = []
    q = deque(sorted(k for k, d in indeg.items() if d == 0))
    while q:
        sid = q.popleft()
        order.append(sid)
        for d in dependents[sid]:
            indeg[d] -= 1
            if indeg[d] == 0:
                q.append(d)
    assert len(order) == len(index), "graph is not acyclic — run validate.py"

    depth = {sid: 0 for sid in index}
    for sid in order:
        for p in prereqs[sid]:
            depth[sid] = max(depth[sid], depth[p] + 1)

    # transitive ancestor/descendant sets with distances, computed once
    anc_d: dict[str, dict[str, int]] = {}
    for sid in index:
        dist: dict[str, int] = {}
        frontier, d = list(prereqs[sid]), 1
        while frontier:
            nxt = []
            for p in frontier:
                if p not in dist:
                    dist[p] = d
                    nxt.extend(prereqs[p])
            frontier, d = nxt, d + 1
        anc_d[sid] = dist

    desc_d: dict[str, dict[str, int]] = defaultdict(dict)
    for sid, dist in anc_d.items():
        for a, d in dist.items():
            desc_d[a][sid] = d

    return index, prereqs, order, depth, anc_d, desc_d


# ── synthetic students ────────────────────────────────────────────────────

def make_student(order, prereqs, depth, theta, rng):
    mastered = {}
    for sid in order:
        if not all(mastered[p] for p in prereqs[sid]):
            mastered[sid] = False
            continue
        b = depth[sid] * 0.45 - 1.6          # deeper skills are harder
        mastered[sid] = rng.random() < 1 / (1 + math.exp(-(theta - b)))
    return mastered


def depth_prior(index, depth):
    md = max(depth.values())
    return {sid: 0.92 - 0.72 * (depth[sid] / md) for sid in index}


# ── metric ────────────────────────────────────────────────────────────────

def balanced_accuracy(belief, mastered, subset=None):
    """Mean of sensitivity and specificity. None if either class is empty."""
    keys = list(subset) if subset is not None else list(belief)
    tp = fn = tn = fp = 0
    for sid in keys:
        pred, truth = belief[sid] >= 0.5, mastered[sid]
        if truth:
            tp += pred
            fn += not pred
        else:
            tn += not pred
            fp += pred
    if (tp + fn) == 0 or (tn + fp) == 0:
        return None
    return (tp / (tp + fn) + tn / (tn + fp)) / 2


def mean_of(values):
    vals = [v for v in values if v is not None]
    return statistics.mean(vals) if vals else float("nan")


# ── the diagnostic under test ─────────────────────────────────────────────

def run_diagnostic(graph, mastered, budget, rng, flat_prior=False):
    index, prereqs, order, depth, anc_d, desc_d = graph

    belief = ({sid: 0.5 for sid in index} if flat_prior
              else dict(depth_prior(index, depth)))

    asked: set[str] = set()
    trace: list[float | None] = []

    for _ in range(budget):
        best, best_score = None, -1.0
        for sid in index:
            if sid in asked:
                continue
            uncertainty = 1.0 - abs(belief[sid] - 0.5) * 2.0
            leverage = len(anc_d[sid]) + len(desc_d[sid])
            score = uncertainty * leverage
            if score > best_score:
                best, best_score = sid, score
        if best is None:
            break

        asked.add(best)
        p = P_CORRECT_IF_MASTERED if mastered[best] else P_CORRECT_IF_NOT
        correct = rng.random() < p

        if correct:
            belief[best] = P_HIGH
            # credit flows UP to prerequisites; effect decays with distance
            for a, d in anc_d[best].items():
                belief[a] += (1.0 - belief[a]) * GAMMA ** d
        else:
            belief[best] = P_LOW
            # blame flows DOWN to dependents; effect decays with distance.
            # NOTE: DESIGN.md §3.4 originally wrote this as
            #     P(x) <- P(x) * gamma**d
            # which makes DISTANT descendants shrink MORE than near ones —
            # backwards. The correct form multiplies by (1 - gamma**d).
            for x, d in desc_d[best].items():
                belief[x] *= (1.0 - GAMMA ** d)

        belief = {k: min(0.999, max(0.001, v)) for k, v in belief.items()}
        trace.append(balanced_accuracy(belief, mastered))

    leaves = [sid for sid in index if not desc_d[sid]]
    internal = [sid for sid in index if desc_d[sid]]
    split = {
        "leaf": balanced_accuracy(belief, mastered, leaves),
        "internal": balanced_accuracy(belief, mastered, internal),
        "leaves_asked": len(asked & set(leaves)),
    }
    return trace, split


# ── main ──────────────────────────────────────────────────────────────────

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", nargs="?", type=Path, default=DEFAULT_PATH)
    ap.add_argument("--students", type=int, default=400)
    ap.add_argument("--budget", type=int, default=40)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()

    graph = load_graph(args.path)
    index, prereqs, order, depth, _, desc_d = graph
    rng = random.Random(args.seed)
    prior = depth_prior(index, depth)

    runs, flat_runs, baselines, splits = [], [], [], []
    skipped = 0

    for _ in range(args.students):
        theta = rng.gauss(0.0, 1.3)
        mastered = make_student(order, prereqs, depth, theta, rng)
        if all(mastered.values()) or not any(mastered.values()):
            skipped += 1          # degenerate: balanced accuracy undefined
            continue
        baselines.append(balanced_accuracy(prior, mastered))
        t, sp = run_diagnostic(graph, mastered, args.budget, rng)
        runs.append(t)
        splits.append(sp)
        t2, _ = run_diagnostic(graph, mastered, args.budget, rng, flat_prior=True)
        flat_runs.append(t2)

    def at(rs, k):
        return mean_of(r[k - 1] for r in rs if len(r) >= k)

    n_leaves = sum(1 for sid in index if not desc_d[sid])
    print(f"\n{len(index)} skills · {len(runs)} students "
          f"({skipped} degenerate, skipped) · budget {args.budget}\n")
    print(f"baseline, 0 items (depth prior alone):  {mean_of(baselines):6.1%}\n")
    print(f"{'items':>6}  {'depth prior':>12}  {'flat prior':>12}")
    for k in (5, 10, 15, 20, 25, 30, 40):
        if k <= args.budget:
            print(f"{k:>6}  {at(runs, k):>11.1%}  {at(flat_runs, k):>11.1%}")

    print(f"\nat {args.budget} items, by graph position:")
    print(f"  internal ({len(index) - n_leaves:>3}, information propagates): "
          f"{mean_of(s['internal'] for s in splits):6.1%}")
    print(f"  leaves   ({n_leaves:>3}, nothing depends on them): "
          f"{mean_of(s['leaf'] for s in splits):6.1%}  "
          f"({mean_of(s['leaves_asked'] for s in splits):.1f} asked directly)")

    print("\nBalanced accuracy = mean of sensitivity and specificity.")
    print("Raw accuracy reads ~87% on this graph and is inflated by easy")
    print("negatives on deep skills that almost nobody masters.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
