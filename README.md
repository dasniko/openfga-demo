# OpenFGA Demo

- [VISUALIZATION.md](VISUALIZATION.md) — model diagrams and the effective access matrix
- [IMPLEMENTATION.md](IMPLEMENTATION.md) — SDK integration for Java, JavaScript and .NET

## Local tests

    fga model test --tests tests/model.fga.yaml

## Store

### Create store

    fga store create --name openfga-demo

### List stores

    fga store list

### Write model

    export FGA_STORE_ID=01K...

    fga model write \
        --store-id=$FGA_STORE_ID \
        --file=model.fga
    
    fga model list --store-id=$FGA_STORE_ID

    export FGA_MODEL_ID=01M...

immutable and versioned

### Write tuples

    fga tuple write \
        --store-id=$FGA_STORE_ID \
        --file=tuples/development.yaml

### Query check

    fga query check \
        --store-id=$FGA_STORE_ID \
        --model-id=$FGA_MODEL_ID \
        user:niko \
        can_view \
        project:foo
