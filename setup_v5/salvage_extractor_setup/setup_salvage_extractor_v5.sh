#!/bin/bash
set -e

echo "--- Setting up Salvage Extractor v2 (Factory-Wide) v5 ---"

# --- 1. Stop and remove the old service ---
echo "[+] Stopping and removing old salvage_extractor service..."
sudo systemctl stop salvage_extractor || true
sudo systemctl disable salvage_extractor || true
sudo rm -f /etc/systemd/system/salvage_extractor.service
sudo rm -rf /factory/workers/processors/salvage_extractor
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/processors/salvage_extractor_v5"
LOG_DIR="/factory/logs"
DB_PATH="/factory/db/salvage_log.db"
RAW_DUMP_DIR="/factory/data/raw/salvaged_text"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $RAW_DUMP_DIR
mkdir -p $(dirname $DB_PATH)

# --- 4. Create Application Files ---
echo "[+] Creating Salvage Extractor v2 application files..."
cat << 'EOF' > $PROJECT_DIR/salvage_extractor.py
import os
import time
import logging
import subprocess
import shutil
import sqlite3
from concurrent.futures import ThreadPoolExecutor

# --- Configuration ---
LOG_DIR = "/factory/logs"
DB_PATH = "/factory/db/salvage_log.db"
RAW_DUMP_DIR = "/factory/data/raw/salvaged_text"
MAX_WORKERS = 4
# Directories to scan for salvageable text
SCAN_PATHS = [
    "/factory/data/discarded",
    "/factory/library/discarded",
    "/factory/library/unsalvageable",
    "/factory/logs"
]
SALVAGEABLE_EXTENSIONS = ['.pdf', '.txt', '.log', '.html', '.json', '.xml']

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    filename=os.path.join(LOG_DIR, 'salvage_extractor.log'),
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logging.getLogger('').addHandler(logging.StreamHandler())

def init_database():
    """Creates a database to track processed files."""
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute('CREATE TABLE IF NOT EXISTS processed_files (filepath TEXT PRIMARY KEY, processed_date TEXT)')
        conn.commit()

def is_file_processed(filepath):
    """Check if a file has already been processed."""
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("SELECT 1 FROM processed_files WHERE filepath=?", (filepath,))
        return c.fetchone() is not None

def mark_file_as_processed(filepath):
    """Adds a file to the database of processed files."""
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("INSERT OR IGNORE INTO processed_files VALUES (?, ?)", (filepath, time.strftime('%Y-%m-%d %H:%M:%S')))
        conn.commit()

def salvage_file(filepath):
    """Attempts to extract raw text from any given file."""
    if is_file_processed(filepath):
        return

    filename = os.path.basename(filepath)
    logging.info(f"Attempting to salvage text from: {filename}")
    
    temp_dir = os.path.join("/tmp", "salvage_temp", str(os.getpid()))
    os.makedirs(temp_dir, exist_ok=True)
    
    output_path = os.path.join(temp_dir, os.path.splitext(filename)[0] + ".txt")
    
    try:
        # Use Calibre for complex formats, simple copy for text-based formats
        if filepath.lower().endswith(('.pdf', '.mobi', '.epub')):
            cmd = ['/opt/calibre/ebook-convert', filepath, output_path]
            result = subprocess.run(cmd, capture_output=True, text=True, errors='ignore', timeout=300)
            if result.returncode != 0:
                raise Exception(f"Calibre conversion failed: {result.stderr.strip()}")
        else: # For .txt, .log, .json etc.
            shutil.copy2(filepath, output_path)

        if os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            shutil.move(output_path, os.path.join(RAW_DUMP_DIR, os.path.basename(output_path)))
            logging.info(f"Successfully salvaged text from {filename}.")
        else:
            logging.warning(f"Salvage attempt for {filename} resulted in an empty file.")

        mark_file_as_processed(filepath)

    except Exception as e:
        logging.error(f"Failed to salvage {filename}: {e}")
        mark_file_as_processed(filepath) # Mark as processed even on failure to prevent loops
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)

def main():
    init_database()
    while True:
        logging.info("--- Salvage Extractor (Factory-Wide) checking for files... ---")
        files_to_process = []
        for path in SCAN_PATHS:
            if os.path.exists(path):
                for dirpath, _, filenames in os.walk(path):
                    for f in filenames:
                        if any(f.lower().endswith(ext) for ext in SALVAGEABLE_EXTENSIONS):
                            files_to_process.append(os.path.join(dirpath, f))
        
        if files_to_process:
            unprocessed_files = [f for f in files_to_process if not is_file_processed(f)]
            if unprocessed_files:
                logging.info(f"Found {len(unprocessed_files)} new files to salvage.")
                with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                    executor.map(salvage_file, unprocessed_files[:50]) # Process in batches of 50
            else:
                logging.info("No new unprocessed files found.")
        else:
            logging.info("No files found in any target directories.")
        
        logging.info("--- Cycle finished. Waiting 5 minutes... ---")
        time.sleep(5 * 60)

if __name__ == "__main__":
    main()
EOF

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/salvage_extractor_v5.service
[Unit]
Description=Salvage Extractor Service v2 (Factory-Wide) v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 salvage_extractor.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting Salvage Extractor v2 service..."
# Corrected chown command targets only the directories this script creates
sudo chown -R $USER:$USER $PROJECT_DIR $RAW_DUMP_DIR $(dirname $DB_PATH)
sudo systemctl daemon-reload
sudo systemctl start salvage_extractor_v5
sudo systemctl enable salvage_extractor_v5

echo "--- Salvage Extractor v2 Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status salvage_extractor_v5"
echo "To watch the logs, run: tail -f /factory/logs/salvage_extractor.log"
