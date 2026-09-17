#!/bin/bash
docker run --rm -it \
  --network host \
  -v "$(pwd)":/workspace -w /workspace \
  openfga/cli:latest "$@"
