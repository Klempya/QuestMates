#!/bin/sh
# Headless tests for QuestMates. Run from anywhere:  sh tests/run.sh
# Uses luajit, lua5.1 or lua (whichever is installed).
cd "$(dirname "$0")/.."
LUA="$(command -v luajit || command -v lua5.1 || command -v lua)"
if [ -z "$LUA" ]; then
  echo "no lua interpreter found (need luajit, lua5.1 or lua)" >&2
  exit 1
fi
exec "$LUA" tests/harness.lua
