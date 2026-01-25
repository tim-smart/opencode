#!/usr/bin/env bash
set -euo pipefail

git fetch origin
git checkout origin/dev

direnv allow

bun install
