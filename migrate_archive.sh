#!/bin/bash
set -e

SOURCE_DIR="/factory/data/archive/raw"
DEST_DIR="/mnt/archive"

echo "--- Migrating Archive Data ---"
echo "Source: $SOURCE_DIR"
echo "Destination: $DEST_DIR"

# Use rsync to move the data
rsync -av --remove-source-files "$SOURCE_DIR/" "$DEST_DIR/"

echo "--- Migration Complete ---"
