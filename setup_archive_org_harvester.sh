#!/bin/bash
set -e

echo "--- Setting up Archive.org Harvester v2 ---"

# --- 1. Stop and remove all old versions to prevent conflicts ---
echo "[+] Stopping and removing all old archive.org collector services..."
sudo systemctl stop archive_org_harvester || true
sudo systemctl disable archive_org_harvester || true
sudo rm -f /etc/systemd/system/archive_org_harvester.service
sudo rm -rf /factory/workers/collectors/archive_org_harvester
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/archive_org_harvester_v2"
LOG_DIR="/factory/logs"
DB_PATH="/factory/db/archive_org_log.db"
BOOK_DEPOSIT_DIR="/library/book_deposit"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $BOOK_DEPOSIT_DIR

# --- 4. Create Application Files ---
echo "[+] Creating archive_org_harvester.py application file..."
cat << 'EOF' > $PROJECT_DIR/archive_org_harvester.py
import os
import time
import logging
import subprocess
import sqlite3
import random
import json

# --- Configuration ---
LOG_DIR = "/factory/logs"
DB_PATH = "/factory/db/archive_org_log.db"
BOOK_DEPOSIT_DIR = "/library/book_deposit"
MAX_DOWNLOADS_PER_CYCLE = 20

# High-value queries for the 'ia' command-line tool
SEARCH_QUERIES = [
    "collection:(cdl) AND mediatype:(texts)",
    "collection:(umass_amherst_libraries) AND mediatype:(texts)",
    "collection:(tischlibrary) AND mediatype:(texts)",
    "subject:('artificial intelligence') AND mediatype:(texts)",
    "subject:('machine learning') AND mediatype:(texts)"
]

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'archive_org_harvester_v2.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def init_database():
    """Creates a database to track processed item identifiers."""
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute('CREATE TABLE IF NOT EXISTS processed_items (identifier TEXT PRIMARY KEY, processed_date TEXT)')
        conn.commit()

def get_item_identifiers_from_api(query):
    """Uses the 'ia' tool to get a list of item identifiers."""
    try:
        logging.info(f"Querying Archive.org for: '{query}'")
        cmd = ['ia', 'search', query, '--itemlist', '--output=json']
        result = subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=300)
        
        if not result.stdout.strip():
            logging.warning("API query returned no results.")
            return []

        identifiers = [json.loads(line)['identifier'] for line in result.stdout.strip().split('\n')]
        logging.info(f"API returned {len(identifiers)} results for query.")
        return identifiers
    except subprocess.CalledProcessError as e:
        logging.error(f"Could not query API for '{query}'. Error: {e.stderr}")
        return []
    except Exception as e:
        logging.error(f"An unexpected error occurred during API query for '{query}': {e}")
        return []

def download_item(identifier):
    """Downloads the best available text format for a given item."""
    try:
        with sqlite3.connect(DB_PATH) as conn:
            c = conn.cursor()
            c.execute("SELECT 1 FROM processed_items WHERE identifier=?", (identifier,))
            if c.fetchone():
                logging.info(f"Skipping already processed item: {identifier}")
                return

        logging.info(f"Processing item: {identifier}")
        cmd = [
            'ia', 'download', identifier,
            '--glob=*.txt', '--glob=*.pdf', '--glob=*.epub',
            '--destdir', BOOK_DEPOSIT_DIR,
            '--no-directories'
        ]
        subprocess.run(cmd, check=True, capture_output=True, timeout=600)
        
        logging.info(f"Successfully downloaded files for item: {identifier}")
        
        with sqlite3.connect(DB_PATH) as conn:
            c = conn.cursor()
            c.execute("INSERT OR IGNORE INTO processed_items VALUES (?, ?)", (identifier, time.strftime('%Y-%m-%d %H:%M:%S')))
            conn.commit()

    except Exception as e:
        logging.error(f"Failed to download item {identifier}: {e.stderr if hasattr(e, 'stderr') else e}")

def main():
    init_database()
    while True:
        logging.info("--- Starting new Archive.org Harvester cycle ---")
        
        query = random.choice(SEARCH_QUERIES)
        item_ids = get_item_identifiers_from_api(query)
        
        if item_ids:
            items_to_process = random.sample(item_ids, min(len(item_ids), MAX_DOWNLOADS_PER_CYCLE))
            logging.info(f"Selected {len(items_to_process)} items to download.")
            
            for item_id in items_to_process:
                download_item(item_id)
                time.sleep(2)
        
        logging.info(f"--- Cycle finished. Waiting 5 minutes... ---")
        time.sleep(5 * 60)

if __name__ == "__main__":
    main()
EOF

cat << 'EOF' > $PROJECT_DIR/requirements.txt
internetarchive
EOF

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. IMPORTANT: Configure the 'ia' tool ---
echo ""
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "!!! ACTION REQUIRED: Please log in to your archive.org account !!!"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo ""
echo "The script will now run 'ia configure'. Please enter your archive.org email and password."
echo "This is a one-time setup to authorize the tool."
echo ""
sudo -u $USER $PROJECT_DIR/venv/bin/ia configure

# --- 7. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/archive_org_harvester_v2.service
[Unit]
Description=Archive.org Harvester Service v2
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 archive_org_harvester.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 8. Start the Service ---
echo "[+] Starting Archive.org Harvester v2 service..."
sudo chown -R $USER:$USER /factory /library
sudo systemctl daemon-reload
sudo systemctl start archive_org_harvester_v2
sudo systemctl enable archive_org_harvester_v2

echo "--- Archive.org Harvester v2 Setup Complete ---"
echo "To check the status, run: sudo systemctl status archive_org_harvester_v2"
echo "To watch the logs, run: tail -f /factory/logs/archive_org_harvester_v2.log"
