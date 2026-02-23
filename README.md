# Greenmask Issue #396 — Minimal Reproduction

Demonstrates that `virtual_references` with multiple polymorphic references on the same FK column **drop one polymorphic type entirely** during subset.

## Schema

No database FK constraints — all relationships via `virtual_references` (mirrors a Rails app with `belongs_to` but no DB-level FKs).

```
accounts (subset root: id = 1)
  → projects (account_id)           [virtual_reference]
      → audits (project_id)         [virtual_reference]
          → controls (audit_id)     [virtual_reference]
      → confirmations (project_id)  [virtual_reference]
          → confirmation_items (confirmation_id) [virtual_reference]

comments (polymorphic via virtual_reference):
  commentable_type = 'Control'          → controls
  commentable_type = 'ConfirmationItem' → confirmation_items
```

## Test Data

| Table | Total rows | In account 1 | In account 2 |
|-------|-----------|--------------|--------------| 
| accounts | 2 | 1 | 1 |
| projects | 2 | 1 | 1 |
| controls | 3 | 2 | 1 |
| confirmation_items | 3 | 2 | 1 |
| comments | 6 | **4 expected** | 2 |

## Run

```bash
# Requires: docker, greenmask (v0.2.x), psql/pg_dump/pg_restore
./reproduce.sh
```

## Expected Output

```
  Table                   Expected    Actual
  -------                 --------    ------
  accounts                1           1
  projects                1           1
  controls                2           2
  confirmation_items      2           2
  comments                4           4       ← both Control and ConfirmationItem comments
```

## Actual Output (v0.2.15)

```
  Table                   Expected    Actual
  -------                 --------    ------
  accounts                1           1
  projects                1           1
  controls                2           2
  confirmation_items      2           2
  comments                4           2       ← Control comments dropped!

  Surviving comment types:
   commentable_type | count
  ------------------+-------
   ConfirmationItem |     2
```

Only `ConfirmationItem` comments survive. All `Control` comments (ids 1, 2) are silently dropped even though the referenced controls (ids 1, 2) are present in the target.

## Key Conditions to Trigger

1. **No database FK constraints** — all relationships via `virtual_references`
2. **Multi-level hierarchy** — polymorphic targets (controls, confirmation_items) are reached through separate branches of the graph, multiple hops from the subset root
3. **Multiple polymorphic references** on the same FK column (`commentable_id`)

A simpler setup (direct `subset_conds` on the target tables, or real DB FKs) does NOT trigger the bug.
