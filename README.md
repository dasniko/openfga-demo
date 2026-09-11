# OpenFGA Demo

- [VISUALIZATION.md](VISUALIZATION.md) — model diagrams and the effective access matrix
- [IMPLEMENTATION.md](IMPLEMENTATION.md) — SDK integration for Java, JavaScript and .NET

## Local tests

Two commands, both offline. `fga model validate` is the cheaper one — it only parses
the DSL and checks the model is well formed (every relation resolves, no cycles, type
restrictions refer to types that exist). It says nothing about whether the model grants
the access you intended:

    fga model validate --file model.fga

    {"is_valid":true,"size_kb":0.45}

That is the syntax gate. `fga model test` is the behavior gate: it spins up an
in-memory OpenFGA instance, loads `model.fga` and the tuples referenced by the test
file, and runs every assertion — no Docker, no store, no network:

    fga model test --tests tests/model.fga.yaml

    # Test Summary #
    Tests 9/9 passing
    Checks 14/14 passing
    ListObjects 8/8 passing
    ListUsers 2/2 passing

Both must be green before finishing any change to the model. Use them while editing;
everything below is for exercising the same model against a real server.

## Store

These commands talk to a running OpenFGA server, so start one first:

    docker compose up -d

That brings up OpenFGA plus Postgres, with HTTP on `:8080` and gRPC on `:8081`.
The CLI defaults to `http://localhost:8080`, so no `--api-url` is needed. If the
server is not up, the commands below do not fail fast — they retry and appear to
hang.

### Create store

A store is the isolation boundary: it owns its own models and tuples, and nothing
crosses between stores. Creating one is the first step, and the `id` it returns is
what every later command needs:

    fga store create --name openfga-demo

    {"store":{"created_at":"2026-09-11T09:29:09.856507Z","id":"01M27WSAEZZ37BC0GB72TSMMGK","name":"openfga-demo","updated_at":"2026-09-11T09:29:09.856507Z"}}

The name is a label for humans; it is not unique, and it is not an identifier.

### List stores

To recover the store id later — for instance in a new shell:

    fga store list

    {"continuation_token":"","stores":[{"created_at":"2026-09-11T09:29:09.856507Z","id":"01M27WSAEZZ37BC0GB72TSMMGK","name":"openfga-demo","updated_at":"2026-09-11T09:29:09.856507Z"}]}

### Write model

Put the store id in the environment so the remaining commands stay readable:

    export FGA_STORE_ID=01K...

Then upload `model.fga`. The CLI parses the DSL and sends the JSON form to the
server, which validates it and returns the id of the model it created:

    fga model write \
        --store-id=$FGA_STORE_ID \
        --file=model.fga

    {"authorization_model_id":"01M27WSEZ0ZR196F9WCJBPECBD"}

Models are immutable and versioned. Writing a model never edits the previous one —
it adds a new version alongside it, and old versions stay queryable forever. So
`model list` is a history, newest first:

    fga model list --store-id=$FGA_STORE_ID

    {"authorization_models":[{"id":"01M27WSEZ0ZR196F9WCJBPECBD","created_at":"2026-09-11T09:29:14.464Z"}]}

    export FGA_MODEL_ID=01M...

This is why queries take a `--model-id`: pinning it makes a check reproducible and
lets you roll a new model out without changing what running code evaluates against.
Omit it and the server uses the latest model, which is convenient for exploring and
risky in production.

### Write tuples

Tuples are the data — the actual relationships between users and objects. Unlike
the model they are not versioned; they are simply written into the store, and a
write takes effect immediately for every model version:

    fga tuple write \
        --store-id=$FGA_STORE_ID \
        --file=tuples/development.yaml

    {"failed_count":0,"successful":[{"object":"organization:acme","relation":"admin","user":"user:carol"},{"object":"organization:acme","relation":"member","user":"user:niko"},{"object":"project:foo","relation":"organization","user":"organization:acme"},{"object":"project:foo","relation":"editor","user":"user:alice"}],"successful_count":4,"time_spent":"10.942959ms","total_count":4}

Only four tuples are needed for this demo — every other access shown below is
derived by the model rather than stored.

### Query check

One yes/no question: may this user perform this action on this one object? This is
the query an application makes before serving a request:

    fga query check \
        --store-id=$FGA_STORE_ID \
        --model-id=$FGA_MODEL_ID \
        user:niko \
        can_view \
        project:foo

    {"allowed":true,"resolution":""}

No tuple grants `niko` anything on `project:foo` directly — they are a member of
`organization:acme`, which owns the project, and the model turns that into
`can_view`. Ask for `can_edit` instead and the answer flips, because membership
does not imply editing:

    {"allowed":false,"resolution":""}

### Query list-objects

Which projects may a user view?

    fga query list-objects \
        --store-id=$FGA_STORE_ID \
        --model-id=$FGA_MODEL_ID \
        user:niko \
        can_view \
        project

    {"objects":["project:foo"]}

`niko` is only an organization member, so the same query for `can_edit` comes back empty:

    fga query list-objects \
        --store-id=$FGA_STORE_ID \
        --model-id=$FGA_MODEL_ID \
        user:niko \
        can_edit \
        project

    {"objects":[]}

Permissions on `organization` work the same way — this is the query behind a
"create project" button:

    fga query list-objects \
        --store-id=$FGA_STORE_ID \
        --model-id=$FGA_MODEL_ID \
        user:carol \
        can_create_project \
        organization

    {"objects":["organization:acme"]}

### Query list-users

Who may view a project? `--user-filter` picks the type to resolve down to — with
`user` you get individual users rather than usersets such as `organization:acme#member`.

    fga query list-users \
        --store-id=$FGA_STORE_ID \
        --model-id=$FGA_MODEL_ID \
        --object project:foo \
        --relation can_view \
        --user-filter user

    {"users":[{"object":{"id":"carol","type":"user"}},{"object":{"id":"niko","type":"user"}},{"object":{"id":"alice","type":"user"}}]}

All three arrive by a different route: `alice` is a direct editor, `carol` an
organization admin, `niko` an organization member. Narrowing to `can_edit` drops
`niko`:

    fga query list-users \
        --store-id=$FGA_STORE_ID \
        --model-id=$FGA_MODEL_ID \
        --object project:foo \
        --relation can_edit \
        --user-filter user

    {"users":[{"object":{"id":"alice","type":"user"}},{"object":{"id":"carol","type":"user"}}]}

Note the argument styles differ: `list-objects` takes user, relation and type as
positional arguments, `list-users` takes named flags.
