# Implementation Guide

How to talk to this store from an application. Examples use the types and permissions
defined in [`model.fga`](model.fga): `organization`, `project`, and the permissions
`can_view`, `can_edit` and `can_create_project`.

> **Check permissions, never roles.** Always check `can_view` / `can_edit` /
> `can_create_project`. The roles `viewer`, `editor`, `member` and `admin` are
> implementation detail of the model and may change — the `can_*` relations are the
> contract with your application. See [`CLAUDE.md`](CLAUDE.md).

## Prerequisites

Start the local server and create a store:

```bash
docker compose up -d

fga store create --name openfga-demo
export FGA_API_URL=http://localhost:8080
export FGA_STORE_ID=01K...

fga model write --store-id=$FGA_STORE_ID --file=model.fga
fga model list --store-id=$FGA_STORE_ID
export FGA_MODEL_ID=01M...

fga tuple write --store-id=$FGA_STORE_ID --file=tuples/development.yaml
```

All SDK examples below read `FGA_API_URL`, `FGA_STORE_ID` and `FGA_MODEL_ID` from the
environment. Pinning `FGA_MODEL_ID` is deliberate: models are immutable and versioned, so
an explicit model ID keeps deployed code on the model version it was tested against. Omit
it only if you want every request to resolve against the latest model.

Authentication is omitted below because the local server runs without it. In production
pass an API token or OAuth2 client credentials through the same configuration object —
read them from the environment, never from source.

### Converting the DSL to JSON

Only the JS SDK can parse `.fga` DSL directly (via `@openfga/syntax-transformer`). Java
has a separate `openfga-language` artifact; .NET has no parser at all. The portable route
is the CLI:

```bash
fga model transform --file model.fga > model.json
```

---

## Java

Requires Java 17+; the examples use Java 21.

**Maven** — current version from
[central.sonatype.com](https://central.sonatype.com/artifact/dev.openfga/openfga-sdk):

```xml
<dependency>
    <groupId>dev.openfga</groupId>
    <artifactId>openfga-sdk</artifactId>
    <version>0.10.0</version>
</dependency>
```

**Client** — create once and reuse; it is thread-safe and holds a connection pool:

```java
import dev.openfga.sdk.api.client.OpenFgaClient;
import dev.openfga.sdk.api.configuration.ClientConfiguration;

var config = new ClientConfiguration()
        .apiUrl(System.getenv("FGA_API_URL"))
        .storeId(System.getenv("FGA_STORE_ID"))
        .authorizationModelId(System.getenv("FGA_MODEL_ID"));

var fgaClient = new OpenFgaClient(config);
```

**Check a permission** — note `_object()` with the leading underscore, since `object` is
not a legal Java identifier here:

```java
import dev.openfga.sdk.api.client.model.ClientCheckRequest;

var request = new ClientCheckRequest()
        .user("user:niko")
        .relation("can_view")
        ._object("project:foo");

boolean allowed = fgaClient.check(request).get().getAllowed();
```

**Authorize creation on the parent** — a project that does not exist yet has no ID, so the
check targets the organization:

```java
var request = new ClientCheckRequest()
        .user("user:carol")
        .relation("can_create_project")
        ._object("organization:acme");

if (fgaClient.check(request).get().getAllowed()) {
    // create the project, then write its organization tuple
}
```

**Write tuples** — after creating a project, link it to its organization:

```java
import dev.openfga.sdk.api.client.model.ClientWriteRequest;
import dev.openfga.sdk.api.model.TupleKey;

var request = new ClientWriteRequest().writes(List.of(
        new TupleKey()
                .user("organization:acme")
                .relation("organization")
                ._object("project:bar"),
        new TupleKey()
                .user("user:carol")
                .relation("editor")
                ._object("project:bar")));

fgaClient.write(request).get();
```

**List the projects a user may see** — for populating an index page:

```java
import dev.openfga.sdk.api.client.model.ClientListObjectsRequest;

var request = new ClientListObjectsRequest()
        .user("user:niko")
        .relation("can_view")
        .type("project");

List<String> projects = fgaClient.listObjects(request).get().getObjects();
// ["project:foo"]
```

**List who can edit a project** — for a sharing dialog:

```java
import dev.openfga.sdk.api.client.model.ClientListUsersRequest;
import dev.openfga.sdk.api.model.FgaObject;
import dev.openfga.sdk.api.model.UserTypeFilter;

var request = new ClientListUsersRequest()
        ._object(new FgaObject().type("project").id("foo"))
        .relation("can_edit")
        .userFilters(List.of(new UserTypeFilter().type("user")));

var users = fgaClient.listUsers(request).get().getUsers();
// user:alice, user:carol
```

**Several permissions on one object** — one round trip instead of three:

```java
import dev.openfga.sdk.api.client.model.ClientListRelationsRequest;

var request = new ClientListRelationsRequest()
        .user("user:niko")
        ._object("project:foo")
        .relations(List.of("can_view", "can_edit"));

var relations = fgaClient.listRelations(request).get().getRelations();
// ["can_view"]
```

Every call returns a `CompletableFuture`. The examples block with `.get()` for brevity;
in a reactive or virtual-thread application, compose with `.thenApply()` instead.

**Loading the model from the DSL** adds a second dependency,
[`dev.openfga:openfga-language`](https://central.sonatype.com/artifact/dev.openfga/openfga-language)
version `0.2.1`:

```java
import dev.openfga.language.DslToJsonTransformer;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.openfga.sdk.api.model.WriteAuthorizationModelRequest;

String dsl = Files.readString(Path.of("model.fga"));
String json = new DslToJsonTransformer().transform(dsl);

var body = new ObjectMapper().readValue(json, WriteAuthorizationModelRequest.class);
String modelId = fgaClient.writeAuthorizationModel(body).get().getAuthorizationModelId();
```

---

## JavaScript / TypeScript

```bash
npm install @openfga/sdk
```

**Client:**

```typescript
import { OpenFgaClient } from '@openfga/sdk';

export const fgaClient = new OpenFgaClient({
  apiUrl: process.env.FGA_API_URL,
  storeId: process.env.FGA_STORE_ID,
  authorizationModelId: process.env.FGA_MODEL_ID,
});
```

**Check a permission:**

```typescript
const { allowed } = await fgaClient.check({
  user: 'user:niko',
  relation: 'can_view',
  object: 'project:foo',
});
```

**Authorize creation on the parent:**

```typescript
const { allowed } = await fgaClient.check({
  user: 'user:carol',
  relation: 'can_create_project',
  object: 'organization:acme',
});
```

**Write tuples:**

```typescript
await fgaClient.writeTuples([
  { user: 'organization:acme', relation: 'organization', object: 'project:bar' },
  { user: 'user:carol', relation: 'editor', object: 'project:bar' },
]);
```

**List the projects a user may see:**

```typescript
const { objects } = await fgaClient.listObjects({
  user: 'user:niko',
  relation: 'can_view',
  type: 'project',
});
// ["project:foo"]
```

**List who can edit a project:**

```typescript
const { users } = await fgaClient.listUsers({
  object: { type: 'project', id: 'foo' },
  relation: 'can_edit',
  user_filters: [{ type: 'user' }],
});
```

**Several permissions on one object** — useful for deciding which buttons to render:

```typescript
const { relations } = await fgaClient.listRelations({
  user: 'user:niko',
  object: 'project:foo',
  relations: ['can_view', 'can_edit'],
});
// ["can_view"]
```

**Many checks at once** — e.g. filtering a list you already hold:

```typescript
const { result } = await fgaClient.batchCheck({
  checks: [
    { user: 'user:niko', relation: 'can_view', object: 'project:foo' },
    { user: 'user:niko', relation: 'can_edit', object: 'project:foo' },
  ],
});
```

Mind the casing asymmetry: request parameters are camelCase, but response bodies come
back in the API's snake_case (`user_filters` going in, `authorization_model_id` coming
out).

---

## .NET

```powershell
dotnet add package OpenFga.Sdk
```

Current version `0.10.4`; supports `net8.0`, `net9.0`, `netstandard2.0` and `net48`.

**Client** — register as a singleton in DI rather than constructing per request:

```csharp
using OpenFga.Sdk.Client;
using OpenFga.Sdk.Configuration;

var configuration = new ClientConfiguration {
    ApiUrl = Environment.GetEnvironmentVariable("FGA_API_URL"),
    StoreId = Environment.GetEnvironmentVariable("FGA_STORE_ID"),
    AuthorizationModelId = Environment.GetEnvironmentVariable("FGA_MODEL_ID"),
};
var fgaClient = new OpenFgaClient(configuration);
```

**Check a permission:**

```csharp
using OpenFga.Sdk.Client.Model;

var response = await fgaClient.Check(new ClientCheckRequest {
    User = "user:niko",
    Relation = "can_view",
    Object = "project:foo",
});
// response.Allowed
```

**Authorize creation on the parent:**

```csharp
var response = await fgaClient.Check(new ClientCheckRequest {
    User = "user:carol",
    Relation = "can_create_project",
    Object = "organization:acme",
});
```

**Write tuples:**

```csharp
await fgaClient.Write(new ClientWriteRequest {
    Writes = new List<ClientTupleKey> {
        new() {
            User = "organization:acme",
            Relation = "organization",
            Object = "project:bar",
        },
        new() {
            User = "user:carol",
            Relation = "editor",
            Object = "project:bar",
        },
    },
});
```

**List the projects a user may see:**

```csharp
var response = await fgaClient.ListObjects(new ClientListObjectsRequest {
    User = "user:niko",
    Relation = "can_view",
    Type = "project",
});
// response.Objects
```

For a large result set, stream instead of materialising the whole list:

```csharp
await foreach (var item in fgaClient.StreamedListObjects(new ClientListObjectsRequest {
    User = "user:niko",
    Relation = "can_view",
    Type = "project",
})) {
    Console.WriteLine(item.Object);
}
```

**List who can edit a project:**

```csharp
using OpenFga.Sdk.Model;

var response = await fgaClient.ListUsers(new ClientListUsersRequest {
    Object = new FgaObject { Type = "project", Id = "foo" },
    Relation = "can_edit",
    UserFilters = new List<UserTypeFilter> { new() { Type = "user" } },
});
```

**Several permissions on one object:**

```csharp
var response = await fgaClient.ListRelations(new ClientListRelationsRequest {
    User = "user:niko",
    Object = "project:foo",
    Relations = new List<string> { "can_view", "can_edit" },
});
// response.Relations
```

---

## Guidance that applies to all three

**Create the client once.** All three SDKs manage an HTTP connection pool internally. A
per-request client exhausts sockets under load. Use a singleton, a DI registration, or an
application-scoped bean.

**Check `can_*`, never a role.** `check(user, "editor", project)` couples your code to the
current role layout; `check(user, "can_edit", project)` survives a model refactor. This is
the whole point of the role/permission split in `model.fga`.

**Authorize creation against the parent.** `can_create_project` is checked on
`organization:acme`, never on the project being created — it does not exist yet and has no
ID. Then write the `organization` tuple as part of creating it, or the new project will be
invisible to everyone.

**Write tuples in the same unit of work as the domain object.** OpenFGA is not part of
your database transaction. If the tuple write fails after the row is committed, you have
an unreachable object; if the row insert fails after the tuple is written, you have a
dangling grant. Pick an order, and make the failure path reconcile.

**Do not check inside a loop.** To filter a collection use `listObjects` (get the
permitted IDs, then fetch those rows) or `batchCheck` for a set you already hold. N checks
for N rows is the most common performance mistake with OpenFGA.

**Let the SDK retry.** All three retry `429` and `5xx` up to three times by default and
honour `Retry-After`. Do not wrap calls in your own retry loop — you will multiply the
built-in attempts.

**Keep `tuples/development.yaml` as the fixture source.** `tests/model.fga.yaml` reads it
directly, so seeding a fresh local store with `fga tuple write` gives you exactly the
state the tests assert against.
