#!/bin/bash
set -e

echo "--- Setting up Smart Router Collector v5 ---"

# --- 1. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/smart_router_collector_v5"
LOG_DIR="/factory/logs"
# Define all the target directories
RAW_TEXT_DIR="/factory/data/raw/routed_text_html"
BOOK_DEPOSIT_DIR="/factory/library/book_deposit"
GEM_INBOX_DIR="/factory/data/inbox/gem_files"
USER="tdf"

# --- 2. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $RAW_TEXT_DIR
mkdir -p $BOOK_DEPOSIT_DIR
mkdir -p $GEM_INBOX_DIR

# --- 3. Create Application Files ---
echo "[+] Creating smart_router_collector.py application file..."
cat << 'EOF' > $PROJECT_DIR/smart_router_collector.py
import os
import time
import logging
import requests
from bs4 import BeautifulSoup
import random
import re
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urlparse

# --- Configuration ---
LOG_DIR = "/factory/logs"
RAW_TEXT_DIR = "/factory/data/raw/routed_text_html"
BOOK_DEPOSIT_DIR = "/factory/library/book_deposit"
GEM_INBOX_DIR = "/factory/data/inbox/gem_files"
MAX_WORKERS = 5

# A diverse list of sources with different file types
SOURCES = [
    {"type": "pdf", "url": "https://arxiv.org/pdf/2308.11063.pdf"},
    {"type": "txt", "url": "https://www.gutenberg.org/files/1342/1342-0.txt"},
    {"type": "html", "url": "https://www.example.com"},
    # Added a real, small ZIP file from archive.org to simulate a Common Crawl/AWS file
    {"type": "zip", "url": "https://archive.org/download/planethuntersviic/planet-hunters-vii-c.zip"},
]

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    filename=os.path.join(LOG_DIR, 'smart_router_collector.log'),
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logging.getLogger('').addHandler(logging.StreamHandler())

def route_and_save_file(content_bytes, original_url, content_type_header):
    """Intelligently routes and saves the file based on its type."""
    try:
        filename = os.path.basename(urlparse(original_url).path)
        if not filename:
            filename = f"index_{int(time.time() * 1000)}.html"

        # Determine destination based on file extension and content type
        if filename.endswith(('.html', '.htm', '.txt')) or 'text' in content_type_header:
            dest_dir = RAW_TEXT_DIR
        elif filename.endswith(('.pdf', '.epub', '.mobi')):
            dest_dir = BOOK_DEPOSIT_DIR
        elif filename.endswith('.zip'):
            dest_dir = GEM_INBOX_DIR
        else:
            # Default fallback for unknown types
            dest_dir = RAW_TEXT_DIR

        os.makedirs(dest_dir, exist_ok=True)
        filepath = os.path.join(dest_dir, filename)
        
        with open(filepath, 'wb') as f:
            f.write(content_bytes)
        logging.info(f"Successfully routed and saved file to {filepath}")

    except Exception as e:
        logging.error(f"Failed to save file for {original_url}: {e}")

def scrape_direct_source(source):
    """Connects to a URL and downloads the raw content."""
    try:
        logging.info(f"Downloading from: {source['url']}")
        response = requests.get(source['url'], timeout=300) # 5 min timeout for large files
        response.raise_for_status()
        
        content_type = response.headers.get('Content-Type', '').lower()
        route_and_save_file(response.content, source['url'], content_type)

    except Exception as e:
        logging.error(f"Failed to download from {source['url']}: {e}", exc_info=True)

def main():
    while True:
        logging.info("--- Starting new Smart Router Collector cycle ---")
        
        # In each cycle, process one random source
        source_to_process = random.choice(SOURCES)
        scrape_direct_source(source_to_process)
        
        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(120)

if __name__ == "__main__":
    main()
EOF

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/smart_router_collector_v5.service
[Unit]
Description=Smart Router Collector Service v5
After=network-online.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 smart_router_collector.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting Smart Router Collector service..."
sudo chown -R $USER:$USER /factory
sudo systemctl daemon-reload
sudo systemctl start smart_router_collector_v5
sudo systemctl enable smart_router_collector_v5

echo "--- Smart Router Collector Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status smart_router_collector_v5"
echo "To watch the logs, run: tail -f /factory/logs/smart_router_collector.log"