#!/bin/bash
set -e

echo "--- Setting up Simple Bulk Text Extractor v5 ---"

# --- 1. Define Paths ---
PROJECT_DIR="/factory/workers/utilities/simple_extractor_v5"
OUTPUT_DIR="/factory/data/raw/from_library/Bulk_Extracted"
USER="tdf"

# --- 2. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $OUTPUT_DIR

# --- 3. Create the extractor ---
echo "[+] Creating extract_all.py file..."
cp /home/tdf/extract_all.py $PROJECT_DIR/extract_all.py

# --- 4. Make the monitor script executable and set permissions ---
chmod +x $PROJECT_DIR/extract_all.py
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $OUTPUT_DIR

echo "--- Simple Bulk Extractor Ready v5 ---"
echo ""
echo "TO RUN:"
echo "cd $PROJECT_DIR"
echo "python3 extract_all.py"
echo ""
echo "This will extract text from ALL files and clear your backlog."
