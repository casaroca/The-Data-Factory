#!/bin/bash
set -e

echo "--- Setting up Common Crawl Harvester v3 (DB Fix) ---"

# --- 1. Stop and remove all old versions to prevent conflicts ---
echo "[+] Stopping and removing all old common_crawl collector services..."
sudo systemctl stop common_crawl_harvester common_crawl_harvester_v2 || true
sudo systemctl disable common_crawl_harvester common_crawl_harvester_v2 || true
sudo rm -f /etc/systemd/system/common_crawl_harvester*.service
sudo rm -rf /factory/workers/collectors/common_crawl_harvester*
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/common_crawl_harvester_v3"
LOG_DIR="/factory/logs"
DB_PATH="/factory/db/common_crawl_log.db"
RAW_DUMP_DIR="/factory/data/raw/common_crawl_harvest"
USER="tdf"

# --- 3. THE FIX: Remove the old, incorrect database file ---
echo "[+] Removing old database file to ensure a clean schema..."
sudo rm -f $DB_PATH

# --- 4. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $RAW_DUMP_DIR
mkdir -p $(dirname $DB_PATH)

# --- 5. Create Application Files ---
echo "[+] Creating common_crawl_harvester_v3.py application file..."
cat << 'EOF' > $PROJECT_DIR/common_crawl_harvester_v3.py
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
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.parse import urlparse
import signal
import sys
from datetime import datetime, timedelta
import tempfile
import shutil

# --- Configuration ---
LOG_DIR = "/factory/logs"
DB_PATH = "/factory/db/common_crawl_log.db"
RAW_DUMP_DIR = "/factory/data/raw/common_crawl_harvest"
MANIFEST_URL = "https://data.commoncrawl.org/crawl-data/CC-MAIN-2024-10/warc.paths.gz"
MANIFEST_LOCAL_PATH = "/tmp/warc.paths.gz"
MAX_WORKERS = 4
CHUNK_SIZE = 8192
MAX_RETRIES = 3
RETRY_DELAY = 30
REQUEST_TIMEOUT = 1800
MIN_TEXT_LENGTH = 250
MAX_PAGES_PER_ARCHIVE = 10000

shutdown_requested = False

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(os.path.join(LOG_DIR, 'common_crawl_harvester_v3.log')),
        logging.StreamHandler()
    ])

def signal_handler(signum, frame):
    global shutdown_requested
    logging.info(f"Received signal {signum}, shutting down gracefully...")
    shutdown_requested = True

signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

def init_database():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute('''CREATE TABLE IF NOT EXISTS processed_archives
                     (path TEXT PRIMARY KEY, 
                      processed_date TEXT,
                      file_size INTEGER,
                      pages_extracted INTEGER,
                      processing_time REAL)''')
        c.execute('''CREATE TABLE IF NOT EXISTS daily_stats
                     (date TEXT PRIMARY KEY,
                      archives_processed INTEGER,
                      total_size_gb REAL,
                      pages_extracted INTEGER)''')
        conn.commit()

def get_daily_stats():
    today = datetime.now().strftime('%Y-%m-%d')
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("SELECT * FROM daily_stats WHERE date = ?", (today,))
        row = c.fetchone()
        if row:
            return {'archives_processed': row[1], 'total_size_gb': row[2], 'pages_extracted': row[3]}
    return {'archives_processed': 0, 'total_size_gb': 0.0, 'pages_extracted': 0}

def update_daily_stats(file_size_bytes, pages_extracted):
    today = datetime.now().strftime('%Y-%m-%d')
    size_gb = file_size_bytes / (1024**3)
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute('''INSERT OR REPLACE INTO daily_stats
                     (date, archives_processed, total_size_gb, pages_extracted)
                    VALUES (?,
                            COALESCE((SELECT archives_processed FROM daily_stats WHERE date = ?), 0) + 1,
                            COALESCE((SELECT total_size_gb FROM daily_stats WHERE date = ?), 0) + ?,
                            COALESCE((SELECT pages_extracted FROM daily_stats WHERE date = ?), 0) + ?)''',
                 (today, today, today, size_gb, today, pages_extracted))
        conn.commit()

def get_unprocessed_archives(all_paths, count=10):
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("SELECT path FROM processed_archives")
        processed = {row[0] for row in c.fetchall()}
    unprocessed = [path for path in all_paths if path not in processed]
    random.shuffle(unprocessed)
    return unprocessed[:count]

def mark_archive_as_processed(path, file_size, pages_extracted, processing_time):
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("""INSERT OR IGNORE INTO processed_archives
                     (path, processed_date, file_size, pages_extracted, processing_time)
                     VALUES (?, ?, ?, ?, ?)""",
                  (path, time.strftime('%Y-%m-%d %H:%M:%S'), file_size, pages_extracted, processing_time))
        conn.commit()

def clean_html(html_content_bytes):
    try:
        soup = BeautifulSoup(html_content_bytes, 'lxml')
    except:
        soup = BeautifulSoup(html_content_bytes, 'html.parser')
    for element in soup(["script", "style", "nav", "footer", "header", "aside", "form", "iframe", "noscript"]):
        element.extract()
    main_content = (soup.find('main') or soup.find('article') or soup.find(class_=re.compile(r'content|main|article', re.I)) or soup.find('body'))
    if main_content:
        text = main_content.get_text(separator=' ', strip=True)
        return re.sub(r'\s+', ' ', text)
    return ""

def download_with_retry(url, max_retries=MAX_RETRIES):
    for attempt in range(max_retries):
        try:
            response = requests.get(url, stream=True, timeout=REQUEST_TIMEOUT, headers={'User-Agent': 'CommonCrawlHarvester/3.0'})
            response.raise_for_status()
            return response
        except Exception as e:
            logging.warning(f"Download attempt {attempt + 1} failed for {url}: {e}")
            if attempt < max_retries - 1:
                time.sleep(RETRY_DELAY * (attempt + 1))
            else:
                raise

def process_warc_archive(warc_path):
    if shutdown_requested: return
    start_time = time.time()
    url = f"https://data.commoncrawl.org/{warc_path}"
    logging.info(f"Processing archive: {os.path.basename(warc_path)}")
    temp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False) as temp_file:
            temp_path = temp_file.name
        
        response = download_with_retry(url)
        file_size = 0
        with open(temp_path, 'wb') as temp_file:
            for chunk in response.iter_content(chunk_size=CHUNK_SIZE):
                if chunk and not shutdown_requested:
                    temp_file.write(chunk)
                    file_size += len(chunk)
                elif shutdown_requested:
                    os.unlink(temp_path); return
        
        all_text_from_archive = []; pages_processed = 0
        with gzip.open(temp_path, 'rb') as gz_file:
            for record in ArchiveIterator(gz_file):
                if shutdown_requested or pages_processed >= MAX_PAGES_PER_ARCHIVE: break
                if (record.rec_type == 'response' and record.http_headers is not None and record.http_headers.get_statuscode() == '200'):
                    try:
                        if 'text/html' not in record.http_headers.get_header('content-type', '').lower(): continue
                        html_bytes = record.content_stream().read()
                        clean_text = clean_html(html_bytes)
                        if len(clean_text) > MIN_TEXT_LENGTH:
                            all_text_from_archive.append(clean_text)
                            pages_processed += 1
                    except Exception as e:
                        logging.debug(f"Error processing record: {e}")
                        continue
        
        if all_text_from_archive:
            output_content = "\n\n--- NEW PAGE ---\n\n".join(all_text_from_archive)
            filename = f"cc_harvest_{os.path.basename(warc_path).replace('.warc.gz', '')}.txt"
            output_path = os.path.join(RAW_DUMP_DIR, filename)
            with open(output_path, 'w', encoding='utf-8') as f: f.write(output_content)
            
            processing_time = time.time() - start_time
            mark_archive_as_processed(warc_path, file_size, len(all_text_from_archive), processing_time)
            update_daily_stats(file_size, len(all_text_from_archive))
            logging.info(f"Successfully extracted {len(all_text_from_archive)} pages ({file_size/1024/1024:.1f}MB) to {filename} in {processing_time:.1f}s")
        else:
            processing_time = time.time() - start_time
            mark_archive_as_processed(warc_path, file_size, 0, processing_time)
            logging.info(f"No usable content found in {os.path.basename(warc_path)}")
    except Exception as e:
        logging.error(f"Failed to process WARC archive {warc_path}: {e}", exc_info=True)
    finally:
        if temp_path and os.path.exists(temp_path):
            os.unlink(temp_path)

def should_continue_today():
    stats = get_daily_stats()
    if stats['total_size_gb'] > 100:
        logging.info(f"Daily limit reached: {stats['total_size_gb']:.1f}GB processed today")
        return False
    return True

def main():
    logging.info("Starting Common Crawl Harvester v3...")
    init_database()
    
    if not os.path.exists(MANIFEST_LOCAL_PATH):
        logging.info(f"Downloading WARC manifest from {MANIFEST_URL}...")
        try:
            response = requests.get(MANIFEST_URL); response.raise_for_status()
            with open(MANIFEST_LOCAL_PATH, 'wb') as f: f.write(response.content)
        except Exception as e:
            logging.error(f"Could not download the manifest file: {e}"); return

    with gzip.open(MANIFEST_LOCAL_PATH, 'rt') as f:
        warc_paths = [line.strip() for line in f]
        logging.info(f"Loaded {len(warc_paths)} WARC paths from manifest")

    while not shutdown_requested and should_continue_today():
        logging.info("--- Starting new harvest cycle ---")
        stats = get_daily_stats()
        logging.info(f"Today's progress: {stats['archives_processed']} archives, {stats['total_size_gb']:.1f}GB, {stats['pages_extracted']} pages")
        
        archives_to_process = get_unprocessed_archives(warc_paths, MAX_WORKERS * 2)
        if not archives_to_process:
            logging.info("All archives from the manifest have been processed."); break
        
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            future_to_archive = {executor.submit(process_warc_archive, archive): archive for archive in archives_to_process}
            for future in as_completed(future_to_archive):
                if shutdown_requested: break
                try: future.result()
                except Exception as e: logging.error(f"Archive {future_to_archive[future]} generated an exception: {e}")
        
        if shutdown_requested: break
        time.sleep(10)
    
    logging.info("Harvester shutdown complete.")

if __name__ == "__main__":
    main()
EOF

echo "[+] Creating requirements.txt..."
cat << 'EOF' > $PROJECT_DIR/requirements.txt
requests>=2.28.0
beautifulsoup4>=4.11.0
warcio>=1.7.0
lxml>=4.9.0
EOF

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install --upgrade pip
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/common_crawl_harvester_v3.service
[Unit]
Description=Common Crawl Harvester Service v3
After=network.target

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
Environment=PYTHONUNBUFFERED=1
ExecStart=$PROJECT_DIR/venv/bin/python3 common_crawl_harvester_v3.py
Restart=on-failure
RestartSec=300
TimeoutStopSec=60
KillMode=mixed
LimitNOFILE=65536
MemoryMax=4G

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Set permissions and start service ---
echo "[+] Setting permissions and starting service..."
sudo chown -R $USER:$USER /factory
sudo systemctl daemon-reload
sudo systemctl start common_crawl_harvester_v3
sudo systemctl enable common_crawl_harvester_v3

echo ""
echo "=== Common Crawl Harvester v3 Setup Complete ==="
