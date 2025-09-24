#!/bin/bash
set -e

echo "--- Setting up Targeted Ebook Collector ---"

# --- 1. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/targeted_collector"
LOG_DIR="/factory/logs"
BOOK_DEPOSIT_DIR="/library/book_deposit"
USER="tdf"

# --- 2. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $BOOK_DEPOSIT_DIR

# --- 3. Create Application Files ---
echo "[+] Creating targeted_collector.py application file..."
cat << 'EOF' > $PROJECT_DIR/targeted_collector.py
import os
import time
import logging
import requests
from bs4 import BeautifulSoup
import random
import re
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urljoin

# --- Configuration ---
LOG_DIR = "/factory/logs"
BOOK_DEPOSIT_DIR = "/library/book_deposit"
MAX_WORKERS = 10
REST_PERIOD_SECONDS = 30 # Updated rest time

# --- List of Target URLs to Scrape ---
# This list can be manually updated as needed.
TARGET_URLS = [
    "https://archive.org/details/cdl",
    "https://archive.org/details/umass_amherst_libraries",
    "https://archive.org/details/tischlibrary",
    "https://archive.org/details/delawarecountydistrictlibrary",
    "https://archive.org/details/computerworld",
    "https://archive.org/details/northeastern",
    "https://archive.org/details/dulua",
    "https://archive.org/details/mugar",
    "https://archive.org/details/aipi.ua-collection",
    "https://archive.org/details/texts?tab=collection&query=artificial+intelligence+llm",
    "https://archive.org/details/texts?tab=collection&query=llm"
]

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'targeted_collector.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def get_ebook_links_from_page(page_url):
    """Scrapes a single page to find all ebook links."""
    try:
        logging.info(f"Fetching ebook links from: {page_url}")
        response = requests.get(page_url, headers={'User-Agent': 'TargetedCollector/1.0'})
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'lxml')
        links = set()
        
        # This selector is specific to archive.org's layout
        links.update(urljoin(page_url, a['href']) for a in soup.select('div.item-tile > a'))

        return list(links)
    except Exception as e:
        logging.error(f"Could not fetch links from {page_url}: {e}")
        return []

def download_book(ebook_page_url):
    """Visits an ebook page, finds the plain text link, and downloads the book."""
    try:
        logging.info(f"Processing book page: {ebook_page_url}")
        response = requests.get(ebook_page_url, headers={'User-Agent': 'TargetedCollector/1.0'})
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'lxml')

        download_url = None
        # Find the most likely plain text download link
        text_link = soup.find('a', string=re.compile(r'FULL TEXT', re.IGNORECASE))
        if text_link:
            download_url = urljoin(ebook_page_url, text_link['href'])

        if not download_url:
            logging.warning(f"No plain text link found for {ebook_page_url}")
            return

        time.sleep(1) # Be respectful
        book_content_response = requests.get(download_url, headers={'User-Agent': 'TargetedCollector/1.0'})
        book_content_response.raise_for_status()

        title = soup.find('h1').text.strip() if soup.find('h1') else f"ebook_{int(time.time())}"
        filename = re.sub(r'[<>:"/\\|?*]', '_', title) + ".txt"
        output_path = os.path.join(BOOK_DEPOSIT_DIR, filename)
        
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(book_content_response.text)
        
        logging.info(f"Successfully downloaded: {filename}")

    except Exception as e:
        logging.error(f"Failed to download book from {ebook_page_url}: {e}", exc_info=True)

def main():
    while True:
        logging.info("--- Starting new Targeted Collector cycle ---")
        
        all_links_to_process = []
        for url in TARGET_URLS:
            all_links_to_process.extend(get_ebook_links_from_page(url))
        
        if all_links_to_process:
            logging.info(f"Found a total of {len(all_links_to_process)} ebooks to download.")
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                executor.map(download_book, all_links_to_process)
        
        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()
EOF

cat << 'EOF' > $PROJECT_DIR/requirements.txt
requests
beautifulsoup4
lxml
EOF

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/targeted_collector.service
[Unit]
Description=Targeted Ebook Collector Service
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 targeted_collector.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting Targeted Ebook Collector service..."
sudo chown -R $USER:$USER /factory /library
sudo systemctl daemon-reload
sudo systemctl start targeted_collector
sudo systemctl enable targeted_collector

echo "--- Targeted Ebook Collector Setup Complete ---"
echo "To check the status, run: sudo systemctl status targeted_collector"
echo "To watch the logs, run: tail -f /factory/logs/targeted_collector.log"
