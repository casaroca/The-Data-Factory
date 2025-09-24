#!/bin/bash
set -e

echo "--- Setting up Common Crawl Query Collector v5 ---"

# --- 1. Stop and remove all old versions to prevent conflicts ---
echo "[+] Stopping and removing all old common_crawl_collector services..."
sudo systemctl stop common_crawl_collector* || true
sudo systemctl disable common_crawl_collector* || true
sudo rm -f /etc/systemd/system/common_crawl_collector*.service
sudo rm -rf /factory/workers/collectors/common_crawl_collector*
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/common_crawl_query_collector_v5"
LOG_DIR="/factory/logs"
RAW_DUMP_DIR="/factory/data/raw/common_crawl_query"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $RAW_DUMP_DIR

# --- 4. Create Application Files ---
echo "[+] Creating common_crawl_query_collector.py application file..."
cat << 'EOF' > $PROJECT_DIR/common_crawl_query_collector.py
import os
import time
import logging
import requests
from bs4 import BeautifulSoup
import random
import re
import json
from concurrent.futures import ThreadPoolExecutor
from warcio.archiveiterator import ArchiveIterator
import gzip
import io

# --- Configuration ---
LOG_DIR = "/factory/logs"
RAW_DUMP_DIR = "/factory/data/raw/common_crawl_query"
MAX_WORKERS = 15
REST_PERIOD_SECONDS = 30 # Updated rest period

# High-quality domains to target
TARGET_DOMAINS = [
    "nytimes.com", "wsj.com", "theguardian.com", "bbc.com", "reuters.com",
    "stackoverflow.com", "github.com", "hbr.org", "forbes.com", "techcrunch.com",
    "mit.edu", "stanford.edu", "arxiv.org"
]
# Using a more recent and valid index
CC_INDEX_URL = "https://index.commoncrawl.org/CC-MAIN-2025-22-index"

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'common_crawl_query_collector.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def get_warc_records_from_api(domain):
    """Queries the Common Crawl CDX API for a specific domain."""
    try:
        # Corrected API query format - searching for a domain directly
        search_url = f"{CC_INDEX_URL}?url=*.{domain}/*&output=json&limit=50"
        logging.info(f"Querying Common Crawl API for domain: {domain}")
        response = requests.get(search_url, headers={'User-Agent': 'CCQueryCollector/1.0'})
        response.raise_for_status()
        # Handle potential empty lines in response
        records = [json.loads(line) for line in response.text.strip().split('\n') if line]
        logging.info(f"API returned {len(records)} records for domain {domain}.")
        return records
    except Exception as e:
        logging.error(f"Could not query CC API for domain {domain}: {e}")
        return []

def clean_html(html_content):
    soup = BeautifulSoup(html_content, 'lxml')
    for element in soup(["script", "style", "nav", "footer", "header", "aside"]):
        element.extract()
    main_content = soup.find('main') or soup.find('article') or soup.find('body')
    return re.sub(r'\s+', ' ', main_content.get_text(strip=True)) if main_content else ""

def fetch_and_process_warc(record):
    """Downloads a WARC segment, extracts text, and saves it."""
    try:
        offset, length = int(record['offset']), int(record['length'])
        url = f"https://data.commoncrawl.org/{record['filename']}"
        headers = {'Range': f'bytes={offset}-{offset + length - 1}'}
        
        logging.info(f"Downloading WARC segment from: {url}")
        warc_response = requests.get(url, headers=headers, stream=True, timeout=120)
        warc_response.raise_for_status()

        # Decompress gzipped content in memory
        with gzip.GzipFile(fileobj=io.BytesIO(warc_response.content)) as gz:
            for record_item in ArchiveIterator(gz):
                if record_item.rec_type == 'response' and record_item.http_headers is not None and record_item.http_headers.get_statuscode() == '200':
                    html = record_item.content_stream().read()
                    clean_text = clean_html(html)
                    if len(clean_text) > 200: # Basic quality filter
                        filename = f"cc_query_{int(time.time() * 1000)}.txt"
                        output_path = os.path.join(RAW_DUMP_DIR, filename)
                        with open(output_path, 'w', encoding='utf-8') as f:
                            f.write(clean_text)
                        logging.info(f"Successfully extracted and saved text to {output_path}")
                        return # Process only the first valid record in the segment

    except Exception as e:
        logging.error(f"Failed to process WARC record {record.get('url')}: {e}", exc_info=True)

def main():
    while True:
        logging.info("--- Starting new Common Crawl Query Collector cycle ---")
        
        domain = random.choice(TARGET_DOMAINS)
        
        warc_records = get_warc_records_from_api(domain)
        
        if warc_records:
            items_to_process = random.sample(warc_records, min(len(warc_records), 10)) # Process more records
            logging.info(f"Selected {len(items_to_process)} WARC records to process.")
            
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                executor.map(fetch_and_process_warc, items_to_process)
        
        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()
EOF

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/common_crawl_query_collector_v5.service
[Unit]
Description=Common Crawl Query Collector Service v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 common_crawl_query_collector.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting Common Crawl Query Collector service..."
sudo chown -R $USER:$USER /factory
sudo systemctl daemon-reload
sudo systemctl start common_crawl_query_collector_v5
sudo systemctl enable common_crawl_query_collector_v5

echo "--- Common Crawl Query Collector Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status common_crawl_query_collector_v5"
echo "To watch the logs, run: tail -f /factory/logs/common_crawl_query_collector.log"
