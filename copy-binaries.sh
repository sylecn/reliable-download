#!/bin/sh
set -e

VERSION=`grep 'cliVersion =' ./lib/RD/CliVersion.hs | cut -d'"' -f2`
TARGET_DIR=build/reliable-download-$VERSION/
mkdir -p "$TARGET_DIR"
cp -f `stack exec -- which rd-api` "$TARGET_DIR"/
cp -f `stack exec -- which rd` "$TARGET_DIR"/
