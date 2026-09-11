# OpenFGA Demo

A small OpenFGA demo store: an authorization model, its tuples, and `.fga.yaml` tests.
Local server via `docker-compose.yml` (OpenFGA + Postgres 18, HTTP on `:8080`, gRPC on `:8081`).

## Layout

| Path | Purpose |
|------|---------|
| `model.fga` | The authorization model (schema 1.1) |
| `tuples/development.yaml` | Relationship tuples — single source of truth, also consumed by the tests |
| `tests/model.fga.yaml` | Check / list_objects / list_users assertions |
| `docker-compose.yml` | Local OpenFGA + Postgres |
| `README.md` | CLI walkthrough (create store, write model, write tuples, query) |
| `IMPLEMENTATION.md` | SDK integration guide — Java, JavaScript/TypeScript, .NET |
| `VISUALIZATION.md` | Mermaid diagrams of the type/relation graph and the access matrix |

## Commands

```bash
fga model validate --file model.fga
fga model test --tests tests/model.fga.yaml
```

Both must be green before finishing any change to the model.

## Model design decisions

**Roles are concentric.** `admin` implies `member` on `organization`; `editor` implies
`viewer` on `project`. Granting the stronger role is enough — never write a second tuple
for the weaker one.

**Organization admins are editors on every project in the org** (`editor: ... or admin from
organization`). This was a deliberate choice, not an accident: admins manage *and* edit
project contents. If admins should only manage projects without editing their contents,
this edge is the thing to change.

**Roles and permissions are separate.** `viewer` / `editor` are assignable roles;
`can_view` / `can_edit` are the permissions applications check. Always check `can_*` from
application code so the role set can evolve without touching callers.

**Creation is authorized on the parent.** `can_create_project` lives on `organization`,
not on `project` — a project that does not exist yet has no ID to check against.

## Testing conventions

`tests/model.fga.yaml` pulls its tuples via `tuple_file: ../tuples/development.yaml`
rather than inlining its own copies. They were previously duplicated in both files and
could drift silently. Add new fixture tuples to `tuples/development.yaml` only.

Tests cover `check`, `list_objects` and `list_users`. When adding a relation, add all
three — `check` alone will not catch a userset that fails to expand.

## Rejected approaches

**`editor` not implying `viewer`.** The original model had `or editor` commented out on
`viewer`, so a project editor could edit a project but not view it, and a test asserted
that as correct. This was a bug; editors are viewers.

**A dangling `organization.admin`.** `admin` was originally defined but referenced by
nothing, giving org admins zero access to any project. Every role must feed into at least
one permission, or it is dead schema.
