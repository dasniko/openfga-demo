# Visualizing the Model

A visual reference for [`model.fga`](model.fga). The diagrams are Mermaid, so they render
directly on GitHub and in most Markdown viewers.

> These diagrams are maintained by hand and can drift from `model.fga`. The model itself is
> the source of truth; the access matrix at the bottom is verified by `fga model test`.

## Types

Three types, one hierarchy edge. A `project` belongs to an `organization`; a `user` can be
attached to either.

```mermaid
flowchart LR
  user(["user"])
  org["organization"]
  proj["project"]

  user -. "admin, member" .-> org
  user -. "editor, viewer" .-> proj
  proj -- "organization" --> org

  classDef t fill:#eef4ff,stroke:#4a6fa5,color:#1a2b44
  classDef u fill:#f5f5f5,stroke:#888,color:#333
  class org,proj t
  class user u
```

Solid arrow = the hierarchy edge stored as a tuple (`project:foo#organization@organization:acme`).
Dotted arrows = roles a user can be granted directly.

## Relations on `organization`

```mermaid
flowchart LR
  admin["admin<br/><i>[user]</i>"]
  member["member<br/><i>[user] or admin</i>"]
  ccp(["can_create_project"])

  admin --> member
  admin --> ccp

  classDef role fill:#eef4ff,stroke:#4a6fa5,color:#1a2b44
  classDef perm fill:#e9f7ef,stroke:#3d8b5f,color:#14331f
  class admin,member role
  class ccp perm
```

An admin is automatically a member, so an admin never needs two tuples. Only admins can
create projects.

## Relations on `project`

```mermaid
flowchart LR
  orgadmin["admin<br/>from organization"]
  orgmember["member<br/>from organization"]
  editor["editor<br/><i>[user] or admin from organization</i>"]
  viewer["viewer<br/><i>[user] or editor or member from organization</i>"]
  canedit(["can_edit"])
  canview(["can_view"])

  orgadmin --> editor
  editor --> viewer
  orgmember --> viewer
  editor --> canedit
  viewer --> canview

  classDef role fill:#eef4ff,stroke:#4a6fa5,color:#1a2b44
  classDef inh fill:#fdf3e3,stroke:#b5893d,color:#4a3714
  classDef perm fill:#e9f7ef,stroke:#3d8b5f,color:#14331f
  class editor,viewer role
  class orgadmin,orgmember inh
  class canedit,canview perm
```

Read the arrows as "implies". Because `editor → viewer → can_view`, anyone who can edit
can also view, and an organization admin picks up both without a single project-level
tuple.

## How a check resolves

`can_view(user:niko, project:foo)` where niko is only a member of the organization:

```mermaid
flowchart TD
  q{{"check: can_view<br/>user:niko @ project:foo"}}
  v["viewer on project:foo?"]
  d["direct viewer tuple?"]
  e["editor on project:foo?"]
  m["member from organization?"]
  o["project:foo#organization<br/>@ organization:acme"]
  mem["organization:acme#member<br/>@ user:niko"]
  yes(["allowed = true"])

  q --> v
  v --> d
  d -- no --> e
  e -- no --> m
  m --> o
  o -- found --> mem
  mem -- found --> yes

  classDef hit fill:#e9f7ef,stroke:#3d8b5f,color:#14331f
  class yes,o,mem hit
```

The last two steps are why the `organization` tuple matters: without it the project is an
orphan and no organization-derived access reaches it.

## The seeded tuples

What [`tuples/development.yaml`](tuples/development.yaml) actually writes:

```mermaid
flowchart LR
  carol(["user:carol"]) -- admin --> acme["organization:acme"]
  niko(["user:niko"]) -- member --> acme
  acme -- organization --> foo["project:foo"]
  alice(["user:alice"]) -- editor --> foo
  bob(["user:bob"])

  classDef obj fill:#eef4ff,stroke:#4a6fa5,color:#1a2b44
  classDef usr fill:#f5f5f5,stroke:#888,color:#333
  classDef orphan fill:#f5f5f5,stroke:#c00,stroke-dasharray:3 3,color:#900
  class acme,foo obj
  class carol,niko,alice usr
  class bob orphan
```

Four tuples. `user:bob` has none, and exists in the tests purely as the negative case.

## Effective access

Derived from those tuples and verified with `fga model test`:

| user | role held | `can_view` foo | `can_edit` foo | `can_create_project` acme |
|------|-----------|:---:|:---:|:---:|
| `user:carol` | `admin` on acme | ✅ | ✅ | ✅ |
| `user:alice` | `editor` on foo | ✅ | ✅ | ❌ |
| `user:niko` | `member` on acme | ✅ | ❌ | ❌ |
| `user:bob` | — | ❌ | ❌ | ❌ |

Carol holds one tuple and gets everything: `admin` implies `member`, and `admin from
organization` implies `editor` on every project in the org, which implies `viewer`. Alice
is the opposite shape — full access to one project, no standing in the organization at
all.

## Generating visualizations

**The bundled Playground** is an interactive model explorer, but it is **off by default**
and this repo's `docker-compose.yml` does not publish its port. To use it, add to the
`openfga` service:

```yaml
    environment:
      - OPENFGA_PLAYGROUND_ENABLED=true
    ports:
      - "3000:3000"
```

Then open <http://localhost:3000/playground>.

**Inspect the model as JSON** — the expanded relation tree, useful when a permission does
not resolve the way the diagrams suggest:

```bash
fga model transform --file model.fga > model.json
```

**Explain a single check** against a running store, which is the fastest way to find a
missing tuple:

```bash
fga query check --store-id=$FGA_STORE_ID user:niko can_view project:foo
fga query expand --store-id=$FGA_STORE_ID can_view project:foo
```

`expand` prints the userset tree for one relation on one object — the concrete form of the
"how a check resolves" diagram above.
