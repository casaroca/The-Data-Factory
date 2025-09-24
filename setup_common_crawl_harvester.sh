#!/bin/bash
set -e

echo "--- Setting up Common Crawl Harvester ---"

# --- 1. Stop and remove all old versions to prevent conflicts ---
echo "[+] Stopping and removing all old common_crawl collector services..."
sudo systemctl stop common_crawl_query_collector common_crawl_bulk_collector || true
sudo systemctl disable common_crawl_query_collector common_crawl_bulk_collector || true
sudo rm -f /etc/systemd/system/common_crawl_*.service
sudo rm -rf /factory/workers/collectors/common_crawl_*
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/common_crawl_harvester"
LOG_DIR="/factory/logs"
DB_PATH="/factory/db/common_crawl_log.db"
RAW_DUMP_DIR="/factory/data/raw/common_crawl_harvest"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $RAW_DUMP_DIR

# --- 4. Create Application Files ---
echo "[+] Creating common_crawl_harvester.py application file..."
cat << 'EOF' > $PROJECT_DIR/common_crawl_harvester.py
import os
import time
import logging
import requests
from bs4 import BeautifulSoup
import random
import re
import json
import sqlite3
from warcio.archiveiterator import ArchiveIterator
import gzip
import io

# --- Configuration ---
LOG_DIR = "/factory/logs"
DB_PATH = "/factory/db/common_crawl_log.db"
RAW_DUMP_DIR = "/factory/data/raw/common_crawl_harvest"
# This file lists all the large .warc.gz archives for a crawl
MANIFEST_URL = "https://data.commoncrawl.org/crawl-data/CC-MAIN-2024-10/warc.paths.gz"
MANIFEST_LOCAL_PATH = "/tmp/warc.paths.gz"

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'common_crawl_harvester.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def init_database():
    """Creates a database to track processed WARC archives."""
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute('CREATE TABLE IF NOT EXISTS processed_archives (path TEXT PRIMARY KEY, processed_date TEXT)')
        conn.commit()

def get_unprocessed_archive(all_paths):
    """Finds one archive path that has not been processed yet."""
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("SELECT path FROM processed_archives")
        processed = {row[0] for row in c.fetchall()}
    
    unprocessed = [path for path in all_paths if path not in processed]
    return random.choice(unprocessed) if unprocessed else None

def mark_archive_as_processed(path):
    """Adds an archive path to the database."""
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("INSERT OR IGNORE INTO processed_archives VALUES (?, ?)", (path, time.strftime('%Y-%m-%d %H:%M:%S')))
        conn.commit()

def clean_html(html_content_bytes):
    """Cleans HTML content, handling potential encoding issues."""
    # Decode the byte string into a regular string, ignoring any characters that can't be decoded.
    # This is more robust than letting the parser guess the encoding.
    html_as_string = html_content_bytes.decode('utf-8', errors='ignore')
    soup = BeautifulSoup(html_as_string, 'html.parser')
    for element in soup(["script", "style", "nav", "footer", "header", "aside"]):
        element.extract()
    main_content = soup.find('main') or soup.find('article') or soup.find('body')
    return re.sub(r'\s+', ' ', main_content.get_text(strip=True)) if main_content else ""

def process_warc_archive(warc_path):
    """Downloads a large WARC archive, extracts all text, and saves it to a single file."""
    try:
        url = f"https://data.commoncrawl.org/{warc_path}"
        logging.info(f"Downloading and processing large archive: {url}")
        
        response = requests.get(url, stream=True, timeout=1800) # 30 minute timeout for download
        response.raise_for_status()

        all_text_from_archive = []
        # Process the gzipped stream in memory
        with gzip.GzipFile(fileobj=response.raw) as gz:
            for record in ArchiveIterator(gz):
                if record.rec_type == 'response' and record.http_headers is not None and record.http_headers.get_statuscode() == '200':
                    # Pass the raw bytes directly to the cleaner
                    html_bytes = record.content_stream().read()
                    clean_text = clean_html(html_bytes)
                    if len(clean_text) > 250: # Quality filter
                        all_text_from_archive.append(clean_text)
        
        if all_text_from_archive:
            output_content = "\n\n--- NEW PAGE ---\n\n".join(all_text_from_archive)
            filename = f"cc_harvest_{os.path.basename(warc_path).replace('.warc.gz', '')}.txt"
            output_path = os.path.join(RAW_DUMP_DIR, filename)
            with open(output_path, 'w', encoding='utf-8') as f:
                f.write(output_content)
            logging.info(f"Successfully extracted {len(all_text_from_archive)} pages to {output_path}")
        
        mark_archive_as_processed(warc_path)

    except Exception as e:
        logging.error(f"Failed to process WARC archive {warc_path}: {e}", exc_info=True)

def main():
    init_database()
    
    # Download the manifest file if it doesn't exist
    if not os.path.exists(MANIFEST_LOCAL_PATH):
        logging.info(f"Downloading WARC manifest from {MANIFEST_URL}...")
        try:
            response = requests.get(MANIFEST_URL)
            response.raise_for_status()
            with open(MANIFEST_LOCAL_PATH, 'wb') as f:
                f.write(response.content)
        except Exception as e:
            logging.error(f"Could not download the manifest file: {e}")
            return

    with gzip.open(MANIFEST_LOCAL_PATH, 'rt') as f:
        warc_paths = [line.strip() for line in f]

    while True:
        logging.info("--- Starting new Common Crawl Harvester cycle ---")
        
        archive_to_process = get_unprocessed_archive(warc_paths)
        
        if archive_to_process:
            process_warc_archive(archive_to_process)
        else:
            logging.info("All archives from the manifest have been processed. Exiting.")
            break # Exit the loop when all are done
        
        logging.info(f"--- Cycle finished. Starting next archive immediately. ---")

if __name__ == "__main__":
    main()
EOF

cat << 'EOF' > $PROJECT_DIR/requirements.txt
requests
beautifulsoup4
warcio
EOF

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/common_crawl_harvester.service
[Unit]
Description=Common Crawl Harvester Service
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 common_crawl_harvester.py
Restart=on-failure
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting Common Crawl Harvester service..."
sudo chown -R $USER:$USER /factory
sudo systemctl daemon-reload
sudo systemctl start common_crawl_harvester
sudo systemctl enable common_crawl_harvester

echo "--- Common Crawl Harvester Setup Complete ---"
echo "To check the status, run: sudo systemctl status common_crawl_harvester"
echo "To watch the logs, run: tail -f /factory/logs/common_crawl_harvester.log"
