-- Curriculum tables: the skill graph.
-- Student-state tables (student_skill, student_misconception, school_scheme,
-- item, attempt) live with the application — see docs/DESIGN.md §4.
--
-- Load:  psql "$DATABASE_URL" -f curriculum/schema.sql
--        python3 curriculum/to_sql.py | psql "$DATABASE_URL"

begin;

create table if not exists skill (
  id            text primary key,
  title         text not null,
  domain        text not null
                  check (domain in ('number','algebra','ratio',
                                    'geometry','probability','statistics')),
  key_stage     text not null check (key_stage in ('KS2','KS3','KS4')),
  tier          text not null check (tier in ('foundation','higher')),
  -- DfE subject content reference (N/A/R/G/P/S), common to all boards.
  -- null = assumed prior knowledge, not in the GCSE spec.
  -- UNVERIFIED against the source document — see curriculum/README.md.
  spec_ref      text,
  constraint ks4_needs_spec_ref
    check (key_stage <> 'KS4' or spec_ref is not null)
);

create table if not exists skill_prereq (
  skill_id      text not null references skill(id) on delete cascade,
  prereq_id     text not null references skill(id) on delete cascade,
  primary key (skill_id, prereq_id),
  constraint no_self_edge check (skill_id <> prereq_id)
);

create index if not exists skill_prereq_prereq_idx on skill_prereq (prereq_id);
create index if not exists skill_domain_idx on skill (domain);
create index if not exists skill_key_stage_idx on skill (key_stage);

-- Acyclicity and the 4-prerequisite cap are NOT expressible as table
-- constraints. They are enforced by curriculum/validate.py, which must run
-- in CI before any load. Do not load a graph that has not passed it.

commit;
