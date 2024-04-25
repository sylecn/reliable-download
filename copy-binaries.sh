#!/bin/sh
set -e

TARGET_DIR=build/
mkdir -p "$TARGET_DIR"
cp -f `stack exec -- which rd-api` "$TARGET_DIR"/
cp -f `stack exec -- which rd` "$TARGET_DIR"/
