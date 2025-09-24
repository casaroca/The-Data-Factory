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
logging.getLogger('urllib3').setLevel(logging.WARNING)
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
        
        logging.info(f"--- Cycle finished. Waiting 2 minutes... ---")
        time.sleep(120)

if __name__ == "__main__":
    main()