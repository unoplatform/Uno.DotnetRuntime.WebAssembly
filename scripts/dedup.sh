#!/bin/bash
set -e

TOPDIR=$(pwd)

mkdir -p /tmp/uno-work

find . -name '*.zip' -exec sh -c 'unzip -d "/tmp/uno-work/${1%.*}" "$1"' _ {} \;

pushd /tmp/uno-work

DIR=$(pwd)

echo "Deduplicating files... in $DIR"
# Find and replace duplicates with symlinks
fdupes -r -1 "$DIR" | while read -r line; do
  files=($line)
  first=${files[0]}
  for file in "${files[@]:1}"; do
    rm "$file"
    ln -s "$(realpath --relative-to="$(dirname "$file")" "$first")" "$file"
  done
done

# Recompress the directory
zip -y -r "$1" "$DIR"

# Clean up
rm -rf "$DIR"

echo "Deduplicated zip file created: $1"

popd