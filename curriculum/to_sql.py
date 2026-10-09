#!/usr/bin/env python3
"""Emit INSERT statements for the skill graph.

    python3 curriculum/to_sql.py | psql "$DATABASE_URL"

Refuses to emit anything if the graph fails validation, so a bad graph cannot
reach the database. Idempotent: re-running updates in place.
"""

from __future__ import annotations

import signal
import sys
from pathlib import Path

import yaml

# Behave like a normal unix filter when the reader goes away (`| head`).
signal.signal(signal.SIGPIPE, signal.SIG_DFL)

sys.path.insert(0, str(Path(__file__).parent))
from validate import (  # noqa: E402
    DEFAULT_PATH, check_edges, check_fields, check_reachability,
    check_tier_consistency, find_cycles, load,
)


def q(value: str | None) -> str:
    if value is None:
        return "null"
    return "'" + value.replace("'", "''") + "'"


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PATH
    skills = load(path)
    index = {s["id"]: s for s in skills if "id" in s}

    errors = check_fields(skills) + check_edges(skills, index)
    cycle_errors, _ = find_cycles(skills, index)
    errors += cycle_errors
    if not cycle_errors:
        errors += check_reachability(skills, index)
        errors += check_tier_consistency(skills, index)
    if errors:
        print(f"refusing to emit SQL: {len(errors)} invariant violation(s). "
              f"Run validate.py.", file=sys.stderr)
        return 1

    out = [
        f"-- generated from {path.name} by to_sql.py — do not edit by hand",
        f"-- {len(skills)} skills",
        "begin;",
        "",
    ]

    for s in skills:
        out.append(
            "insert into skill (id, title, domain, key_stage, tier, spec_ref) values "
            f"({q(s['id'])}, {q(s['title'])}, {q(s['domain'])}, "
            f"{q(s['key_stage'])}, {q(s['tier'])}, {q(s['spec_ref'])})\n"
            "  on conflict (id) do update set "
            "title = excluded.title, domain = excluded.domain, "
            "key_stage = excluded.key_stage, tier = excluded.tier, "
            "spec_ref = excluded.spec_ref;"
        )

    out.append("")
    # Replace the edge set wholesale: an edge removed from the YAML must
    # disappear from the database, which an upsert alone would not do.
    out.append("delete from skill_prereq;")
    for s in skills:
        for p in s.get("prereqs") or []:
            out.append(
                "insert into skill_prereq (skill_id, prereq_id) values "
                f"({q(s['id'])}, {q(p)});"
            )

    out += ["", "commit;"]
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
