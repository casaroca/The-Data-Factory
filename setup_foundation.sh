#!/bin/bash
set -e

# --- Configuration ---
USER="tdf"

echo "--- Building The Data Factory Foundation ---"

# --- STAGE 1: EXPAND THE MAIN FILESYSTEM ---
echo "[+] STAGE 1: Expanding the main filesystem to use all available space..."
sudo lvextend -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv
sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv

# --- STAGE 2: SYSTEM UPDATES & DEPENDENCIES ---
echo "[+] STAGE 2: Installing system updates and all required dependencies..."
export NEEDRESTART_MODE=a
sudo apt-get update
sudo apt-get install -y nano python3-venv rsync sqlite3 tree \
                        libegl1 libopengl0 libxcb-cursor0 libnss3 \
                        zstd tesseract-ocr poppler-utils unzip \
                        lvm2 parted psmisc

# --- STAGE 3: CREATE DIRECTORY STRUCTURE ---
echo "[+] STAGE 3: Creating complete data factory directory structure..."
# Since everything is on one drive, we create our main folders in the root directory
# and the library will now live inside /factory for a fully unified structure.
sudo mkdir -p "/factory/workers/collectors"
sudo mkdir -p "/factory/workers/sorters"
sudo mkdir -p "/factory/workers/processors"
sudo mkdir -p "/factory/workers/organizers"
sudo mkdir -p "/factory/workers/extractors"
sudo mkdir -p "/factory/workers/monitors"
sudo mkdir -p "/factory/logs"
sudo mkdir -p "/factory/db"
sudo mkdir -p "/factory/data/inbox"
sudo mkdir -p "/factory/data/archive/raw"
sudo mkdir -p "/factory/data/raw"
sudo mkdir -p "/factory/data/processed"
sudo mkdir -p "/factory/data/tagged"
sudo mkdir -p "/factory/data/final/instructions/jsonl"
sudo mkdir -p "/factory/data/final/instructions/csv"
sudo mkdir -p "/factory/data/final/prompts/jsonl"
sudo mkdir -p "/factory/data/final/prompts/csv"
sudo mkdir -p "/factory/data/final/packages"
sudo mkdir -p "/factory/data/discarded"
sudo mkdir -p "/factory/library/book_deposit"
sudo mkdir -p "/factory/library/library"
sudo mkdir -p "/factory/library/discarded"
sudo mkdir -p "/factory/library/media_for_processing"

# --- 4. Set Final Ownership ---
echo "[+] STAGE 4: Setting final ownership for the '$USER' user..."
sudo chown -R $USER:$USER /factory

echo ""
echo "--- Foundation Setup Complete! ---"
echo "The server is now fully prepared for the data factory installation."
