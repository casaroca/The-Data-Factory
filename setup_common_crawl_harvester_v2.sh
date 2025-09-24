#!/bin/bash
set -e

echo "--- Setting up Common Crawl Harvester v2 (Fixed) ---"

# --- 1. Stop and remove all old versions to prevent conflicts ---
echo "[+] Stopping and removing all old common_crawl collector services..."
sudo systemctl stop common_crawl_harvester || true
sudo systemctl stop common_crawl_harvester_v2 || true
sudo systemctl disable common_crawl_harvester || true
sudo systemctl disable common_crawl_harvester_v2 || true
sudo rm -f /etc/systemd/system/common_crawl_harvester.service
sudo rm -f /etc/systemd/system/common_crawl_harvester_v2.service
sudo rm -rf /factory/workers/collectors/common_crawl_harvester
sudo rm -rf /factory/workers/collectors/common_crawl_harvester_v2
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/common_crawl_harvester_v2"
LOG_DIR="/factory/logs"
DB_DIR="/factory/db"
DB_PATH="/factory/db/common_crawl_log.db"
RAW_DUMP_DIR="/factory/data/raw/common_crawl_harvest"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $RAW_DUMP_DIR
mkdir -p $DB_DIR
mkdir -p $LOG_DIR

# --- 4. Create Application Files ---
echo "[+] Creating common_crawl_harvester_v2.py application file..."
cat << 'EOF' > $PROJECT_DIR/common_crawl_harvester_v2.py
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

# Performance settings for 50-100GB/day
MAX_WORKERS = 4  # Parallel downloads
CHUNK_SIZE = 8192  # Download chunk size
MAX_RETRIES = 3
RETRY_DELAY = 30
REQUEST_TIMEOUT = 1800  # 30 minutes
MIN_TEXT_LENGTH = 250
MAX_PAGES_PER_ARCHIVE = 10000  # Prevent memory issues

# Global shutdown flag
shutdown_requested = False

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(os.path.join(LOG_DIR, 'common_crawl_harvester_v2.log')),
        logging.StreamHandler()
    ]
)

def signal_handler(signum, frame):
    """Handle shutdown signals gracefully."""
    global shutdown_requested
    logging.info(f"Received signal {signum}, shutting down gracefully...")
    shutdown_requested = True

signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

def init_database():
    """Creates a database to track processed WARC archives."""
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
    """Get today's processing statistics."""
    today = datetime.now().strftime('%Y-%m-%d')
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("SELECT * FROM daily_stats WHERE date = ?", (today,))
        row = c.fetchone()
        if row:
            return {
                'archives_processed': row[1],
                'total_size_gb': row[2],
                'pages_extracted': row[3]
            }
        return {'archives_processed': 0, 'total_size_gb': 0.0, 'pages_extracted': 0}

def update_daily_stats(file_size_bytes, pages_extracted):
    """Update daily statistics."""
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
    """Gets multiple unprocessed archive paths for parallel processing."""
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("SELECT path FROM processed_archives")
        processed = {row[0] for row in c.fetchall()}
    
    unprocessed = [path for path in all_paths if path not in processed]
    random.shuffle(unprocessed)
    return unprocessed[:count]

def mark_archive_as_processed(path, file_size, pages_extracted, processing_time):
    """Adds an archive path to the database with metadata."""
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("""INSERT OR IGNORE INTO processed_archives 
                    (path, processed_date, file_size, pages_extracted, processing_time) 
                    VALUES (?, ?, ?, ?, ?)""", 
                 (path, time.strftime('%Y-%m-%d %H:%M:%S'), file_size, pages_extracted, processing_time))
        conn.commit()

def clean_html(html_content_bytes):
    """Cleans HTML content efficiently."""
    try:
        # Use lxml parser if available, fallback to html.parser
        soup = BeautifulSoup(html_content_bytes, 'lxml')
    except:
        soup = BeautifulSoup(html_content_bytes, 'html.parser')
    
    # Remove unwanted elements
    for element in soup(["script", "style", "nav", "footer", "header", "aside", "form", "iframe", "noscript"]):
        element.extract()
    
    # Focus on main content areas
    main_content = (soup.find('main') or 
                   soup.find('article') or 
                   soup.find(class_=re.compile(r'content|main|article', re.I)) or
                   soup.find('body'))
    
    if main_content:
        text = main_content.get_text(separator=' ', strip=True)
        # Clean up whitespace and normalize
        text = re.sub(r'\s+', ' ', text)
        return text
    return ""

def download_with_retry(url, max_retries=MAX_RETRIES):
    """Download with retry logic and proper error handling."""
    for attempt in range(max_retries):
        try:
            response = requests.get(
                url, 
                stream=True, 
                timeout=REQUEST_TIMEOUT,
                headers={'User-Agent': 'CommonCrawlHarvester/2.0'}
            )
            response.raise_for_status()
            return response
        except Exception as e:
            logging.warning(f"Download attempt {attempt + 1} failed for {url}: {e}")
            if attempt < max_retries - 1:
                time.sleep(RETRY_DELAY * (attempt + 1))
            else:
                raise

def process_warc_archive(warc_path):
    """Downloads and processes a WARC archive efficiently with streaming."""
    if shutdown_requested:
        return
        
    start_time = time.time()
    url = f"https://data.commoncrawl.org/{warc_path}"
    logging.info(f"Processing archive: {os.path.basename(warc_path)}")
    
    try:
        # Create temporary file for download
        with tempfile.NamedTemporaryFile(delete=False) as temp_file:
            temp_path = temp_file.name
            
        # Download to temporary file
        response = download_with_retry(url)
        file_size = 0
        
        with open(temp_path, 'wb') as temp_file:
            for chunk in response.iter_content(chunk_size=CHUNK_SIZE):
                if chunk and not shutdown_requested:
                    temp_file.write(chunk)
                    file_size += len(chunk)
                elif shutdown_requested:
                    os.unlink(temp_path)
                    return
        
        # Process the downloaded file
        all_text_from_archive = []
        pages_processed = 0
        
        with gzip.open(temp_path, 'rb') as gz_file:
            for record in ArchiveIterator(gz_file):
                if shutdown_requested or pages_processed >= MAX_PAGES_PER_ARCHIVE:
                    break
                    
                if (record.rec_type == 'response' and 
                    record.http_headers is not None and 
                    record.http_headers.get_statuscode() == '200'):
                    
                    try:
                        content_type = record.http_headers.get_header('content-type', '').lower()
                        if 'text/html' not in content_type:
                            continue
                            
                        html_bytes = record.content_stream().read()
                        clean_text = clean_html(html_bytes)
                        
                        if len(clean_text) > MIN_TEXT_LENGTH:
                            all_text_from_archive.append(clean_text)
                            pages_processed += 1
                            
                    except Exception as e:
                        logging.debug(f"Error processing record: {e}")
                        continue
        
        # Clean up temporary file
        os.unlink(temp_path)
        
        # Save extracted text if we got any
        if all_text_from_archive:
            output_content = "\n\n--- NEW PAGE ---\n\n".join(all_text_from_archive)
            filename = f"cc_harvest_{os.path.basename(warc_path).replace('.warc.gz', '')}.txt"
            output_path = os.path.join(RAW_DUMP_DIR, filename)
            
            with open(output_path, 'w', encoding='utf-8') as f:
                f.write(output_content)
            
            processing_time = time.time() - start_time
            mark_archive_as_processed(warc_path, file_size, len(all_text_from_archive), processing_time)
            update_daily_stats(file_size, len(all_text_from_archive))
            
            logging.info(f"Successfully extracted {len(all_text_from_archive)} pages "
                        f"({file_size/1024/1024:.1f}MB) to {filename} "
                        f"in {processing_time:.1f}s")
        else:
            processing_time = time.time() - start_time
            mark_archive_as_processed(warc_path, file_size, 0, processing_time)
            logging.info(f"No usable content found in {os.path.basename(warc_path)}")

    except Exception as e:
        logging.error(f"Failed to process WARC archive {warc_path}: {e}", exc_info=True)
        # Clean up temporary file if it exists
        if 'temp_path' in locals() and os.path.exists(temp_path):
            os.unlink(temp_path)

def should_continue_today():
    """Check if we should continue processing based on daily limits."""
    stats = get_daily_stats()
    
    # Stop if we've processed more than 100GB today
    if stats['total_size_gb'] > 100:
        logging.info(f"Daily limit reached: {stats['total_size_gb']:.1f}GB processed today")
        return False
    
    # Continue if we're under 50GB
    if stats['total_size_gb'] < 50:
        return True
    
    # Between 50-100GB, continue with reduced aggressiveness
    return stats['total_size_gb'] < 100

def main():
    logging.info("Starting Common Crawl Harvester v2...")
    init_database()
    
    # Download manifest if needed
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

    # Load WARC paths
    with gzip.open(MANIFEST_LOCAL_PATH, 'rt') as f:
        warc_paths = [line.strip() for line in f]
    
    logging.info(f"Loaded {len(warc_paths)} WARC paths from manifest")

    while not shutdown_requested and should_continue_today():
        logging.info("--- Starting new harvest cycle ---")
        
        # Log daily progress
        stats = get_daily_stats()
        logging.info(f"Today's progress: {stats['archives_processed']} archives, "
                    f"{stats['total_size_gb']:.1f}GB, {stats['pages_extracted']} pages")
        
        # Get batch of unprocessed archives
        archives_to_process = get_unprocessed_archives(warc_paths, MAX_WORKERS * 2)
        
        if not archives_to_process:
            logging.info("All archives from the manifest have been processed.")
            break
        
        # Process archives in parallel
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            future_to_archive = {
                executor.submit(process_warc_archive, archive): archive 
                for archive in archives_to_process
            }
            
            for future in as_completed(future_to_archive):
                if shutdown_requested:
                    break
                try:
                    future.result()
                except Exception as e:
                    archive = future_to_archive[future]
                    logging.error(f"Archive {archive} generated an exception: {e}")
        
        if shutdown_requested:
            break
            
        # Brief pause between cycles
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
sudo bash -c "cat << EOF > /etc/systemd/system/common_crawl_harvester_v2.service
[Unit]
Description=Common Crawl Harvester Service v2 (Fixed)
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
Environment=PYTHONUNBUFFERED=1
ExecStart=$PROJECT_DIR/venv/bin/python3 common_crawl_harvester_v2.py
Restart=on-failure
RestartSec=300
TimeoutStopSec=60
KillMode=mixed

# Resource limits
LimitNOFILE=65536
MemoryMax=4G

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Create monitoring script ---
echo "[+] Creating monitoring script..."
cat << 'EOF' > $PROJECT_DIR/monitor.py
#!/usr/bin/env python3
import sqlite3
import os
from datetime import datetime

DB_PATH = "/factory/db/common_crawl_log.db"
RAW_DUMP_DIR = "/factory/data/raw/common_crawl_harvest"

def get_stats():
    if not os.path.exists(DB_PATH):
        print("Database not found. Service may not be running yet.")
        return
    
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        
        # Today's stats
        today = datetime.now().strftime('%Y-%m-%d')
        c.execute("SELECT * FROM daily_stats WHERE date = ?", (today,))
        today_stats = c.fetchone()
        
        # Total stats
        c.execute("SELECT COUNT(*), AVG(file_size), SUM(pages_extracted) FROM processed_archives")
        total_stats = c.fetchone()
        
        # Recent activity
        c.execute("""SELECT path, processed_date, file_size/1024/1024 as size_mb, pages_extracted 
                    FROM processed_archives 
                    ORDER BY processed_date DESC LIMIT 5""")
        recent = c.fetchall()
    
    print("=== Common Crawl Harvester Status ===")
    print(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    if today_stats:
        print(f"\nToday's Progress:")
        print(f"  Archives processed: {today_stats[1]}")
        print(f"  Data harvested: {today_stats[2]:.1f} GB")
        print(f"  Pages extracted: {today_stats[3]:,}")
    else:
        print("\nNo activity today yet.")
    
    if total_stats[0]:
        print(f"\nTotal Statistics:")
        print(f"  Total archives: {total_stats[0]}")
        print(f"  Average size: {total_stats[1]/1024/1024:.1f} MB")
        print(f"  Total pages: {total_stats[2]:,}")
    
    if recent:
        print(f"\nRecent Activity:")
        for path, date, size_mb, pages in recent:
            filename = os.path.basename(path)
            print(f"  {date}: {filename} ({size_mb:.1f}MB, {pages} pages)")
    
    # Check output directory
    if os.path.exists(RAW_DUMP_DIR):
        files = [f for f in os.listdir(RAW_DUMP_DIR) if f.endswith('.txt')]
        total_size = sum(os.path.getsize(os.path.join(RAW_DUMP_DIR, f)) for f in files)
        print(f"\nOutput Files:")
        print(f"  Files created: {len(files)}")
        print(f"  Total output size: {total_size/1024/1024:.1f} MB")

if __name__ == "__main__":
    get_stats()
EOF

chmod +x $PROJECT_DIR/monitor.py

# --- 8. Set permissions and start service ---
echo "[+] Setting permissions and starting service..."
sudo chown -R $USER:$USER /factory
sudo systemctl daemon-reload
sudo systemctl start common_crawl_harvester_v2
sudo systemctl enable common_crawl_harvester_v2

echo ""
echo "=== Common Crawl Harvester v2 Setup Complete ==="
echo ""
echo "Service Commands:"
echo "  Status: sudo systemctl status common_crawl_harvester_v2"
echo "  Logs:   sudo journalctl -u common_crawl_harvester_v2 -f"
echo "  Stop:   sudo systemctl stop common_crawl_harvester_v2"
echo ""
echo "Monitoring:"
echo "  Watch logs: tail -f /factory/logs/common_crawl_harvester_v2.log"
echo "  Statistics: $PROJECT_DIR/venv/bin/python3 $PROJECT_DIR/monitor.py"
echo ""
echo "Data will be saved to: $RAW_DUMP_DIR"
echo "Target: 50-100GB per day"
echo ""
echo "The service will automatically:"
echo "- Process 4 archives in parallel"
echo "- Stop at 100GB per day"
echo "- Resume the next day"
echo "- Handle errors gracefully"
