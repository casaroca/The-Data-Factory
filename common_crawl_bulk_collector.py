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
RAW_DUMP_DIR = "/factory/data/raw/common_crawl_bulk"
# This file lists all the large .warc.gz archives for a crawl
MANIFEST_URL = "https://data.commoncrawl.org/crawl-data/CC-MAIN-2024-10/warc.paths.gz"
MANIFEST_LOCAL_PATH = "/tmp/warc.paths.gz"
REST_PERIOD_SECONDS = 10

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'common_crawl_bulk_collector.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def init_database():
    """Creates a database to track processed WARC archives."""
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
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

def clean_html(html_content):
    try:
        # Try parsing as XML first
        soup = BeautifulSoup(html_content, 'lxml-xml')
    except Exception:
        # If that fails, parse as HTML
        soup = BeautifulSoup(html_content, 'lxml')

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

        filename = f"cc_bulk_{os.path.basename(warc_path).replace('.warc.gz', '')}.txt"
        output_path = os.path.join(RAW_DUMP_DIR, filename)
        page_count = 0

        with open(output_path, 'w', encoding='utf-8') as f_out:
            # Process the gzipped stream in memory
            with gzip.GzipFile(fileobj=response.raw) as gz:
                for record in ArchiveIterator(gz):
                    if record.rec_type == 'response' and record.http_headers is not None and record.http_headers.get_statuscode() == '200':
                        html = record.content_stream().read()
                        clean_text = clean_html(html)
                        if len(clean_text) > 250: # Quality filter
                            f_out.write(clean_text)
                            f_out.write("\n\n--- NEW PAGE ---\n\n")
                            page_count += 1
        
        if page_count > 0:
            logging.info(f"Successfully extracted {page_count} pages to {output_path}")
        else:
            os.remove(output_path)
            logging.info(f"No pages met the quality filter in {warc_path}. Removed empty file.")

        mark_archive_as_processed(warc_path)

    except Exception as e:
        logging.error(f"Failed to process WARC archive {warc_path}: {e}", exc_info=True)

def main():
    init_database()
    
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
        logging.info("--- Starting new Common Crawl Bulk Collector cycle ---")
        
        archive_to_process = get_unprocessed_archive(warc_paths)
        
        if archive_to_process:
            process_warc_archive(archive_to_process)
        else:
            logging.info("All archives from the manifest have been processed. Exiting.")
            break 
        
        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()