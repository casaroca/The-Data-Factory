#!/bin/bash
set -e

echo "--- Setting up Archive.org Harvester v2 (Fixed) ---"

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
# THE FIX: Define the absolute path to the 'ia' executable within its venv
IA_EXECUTABLE = "/factory/workers/collectors/archive_org_harvester_v2/venv/bin/ia"

# High-value queries for the 'ia' command-line tool
SEARCH_QUERIES = [
    "encyclopedia format:pdf", "dictionary format:pdf", "almanac format:pdf", "thesaurus format:pdf", "atlas format:pdf",
    "yearbook format:pdf", "factbook format:pdf", "compendium format:pdf", "gazetteer format:pdf", "manual of general knowledge format:pdf",
    "subject:\"philosophy\" format:pdf", "subject:\"logic and reasoning\" format:pdf", "subject:\"critical thinking\" format:pdf",
    "subject:\"epistemology\" format:pdf", "subject:\"metaphysics\" format:pdf", "subject:\"ethics\" format:pdf",
    "subject:\"moral philosophy\" format:pdf", "subject:\"stoicism\" format:pdf", "subject:\"existentialism\" format:pdf",
    "subject:\"political philosophy\" format:pdf", "subject:\"world history\" format:pdf", "subject:\"ancient history\" format:pdf",
    "subject:\"medieval history\" format:pdf", "subject:\"renaissance history\" format:pdf", "subject:\"modern history\" format:pdf",
    "subject:\"history of science\" format:pdf", "subject:\"military history\" format:pdf", "subject:\"history of philosophy\" format:pdf",
    "subject:\"cultural history\" format:pdf", "biographies historical figures format:pdf", "subject:\"classic literature\" format:pdf",
    "subject:\"world literature\" format:pdf", "subject:\"english literature\" format:pdf", "subject:\"american literature\" format:pdf",
    "subject:\"poetry anthology\" format:pdf", "subject:\"drama plays\" format:pdf", "subject:\"folklore\" format:pdf",
    "subject:\"mythology\" format:pdf", "subject:\"linguistics\" format:pdf", "subject:\"comparative literature\" format:pdf",
    "subject:\"sociology\" format:pdf", "subject:\"anthropology\" format:pdf", "subject:\"political science\" format:pdf",
    "subject:\"economics\" format:pdf", "subject:\"psychology\" format:pdf", "subject:\"geography human\" format:pdf",
    "subject:\"demography\" format:pdf", "subject:\"education theory\" format:pdf", "subject:\"law and legal texts\" format:pdf",
    "subject:\"international relations\" format:pdf", "subject:\"physics textbooks\" format:pdf", "subject:\"chemistry textbooks\" format:pdf",
    "subject:\"biology textbooks\" format:pdf", "subject:\"astronomy textbooks\" format:pdf", "subject:\"earth science\" format:pdf",
    "subject:\"mathematics textbooks\" format:pdf", "subject:\"geometry texts\" format:pdf", "subject:\"algebra textbooks\" format:pdf",
    "subject:\"calculus textbooks\" format:pdf", "subject:\"statistics textbooks\" format:pdf", "subject:\"computer science textbooks\" format:pdf",
    "subject:\"programming manuals\" format:pdf", "subject:\"artificial intelligence early\" format:pdf", "subject:\"machine learning classic\" format:pdf",
    "subject:\"data structures algorithms\" format:pdf", "subject:\"electronics textbooks\" format:pdf", "subject:\"mechanical engineering\" format:pdf",
    "subject:\"civil engineering\" format:pdf", "subject:\"electrical engineering\" format:pdf", "subject:\"information theory\" format:pdf",
    "subject:\"medical textbooks\" format:pdf", "subject:\"anatomy textbooks\" format:pdf", "subject:\"physiology textbooks\" format:pdf",
    "subject:\"pathology\" format:pdf", "subject:\"pharmacology\" format:pdf", "subject:\"epidemiology\" format:pdf",
    "subject:\"public health\" format:pdf", "subject:\"nursing textbooks\" format:pdf", "subject:\"psychology clinical\" format:pdf",
    "subject:\"nutrition science\" format:pdf", "subject:\"art history\" format:pdf", "subject:\"music theory\" format:pdf",
    "subject:\"architecture history\" format:pdf", "subject:\"design principles\" format:pdf", "subject:\"aesthetics philosophy\" format:pdf",
    "subject:\"theater studies\" format:pdf", "subject:\"film studies\" format:pdf", "subject:\"cultural studies\" format:pdf",
    "subject:\"religion comparative\" format:pdf", "subject:\"mythology comparative\" format:pdf", "puzzles and riddles format:pdf",
    "chess manuals format:pdf", "go strategy format:pdf", "mathematical logic format:pdf", "problem solving techniques format:pdf",
    "IQ tests format:pdf", "reasoning tests format:pdf", "lateral thinking format:pdf", "debate handbooks format:pdf", "critical essays format:pdf"
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
        cmd = [IA_EXECUTABLE, 'search', query, '--itemlist', '--output=json']
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
            IA_EXECUTABLE, 'download', identifier,
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
        
        logging.info(f"--- Cycle finished. Waiting 60 seconds... ---")
        time.sleep(60)

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
