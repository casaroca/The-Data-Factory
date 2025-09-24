#!/bin/bash
set -e

echo "--- Setting up Targeted Ebook Collector v2 (Deep Crawl) ---"

# --- 1. Stop and remove the old service to prevent conflicts ---
echo "[+] Stopping and removing old targeted_collector service..."
sudo systemctl stop targeted_collector || true
sudo systemctl disable targeted_collector || true
sudo rm -f /etc/systemd/system/targeted_collector.service
sudo rm -rf /factory/workers/collectors/targeted_collector
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/targeted_collector_v2"
LOG_DIR="/factory/logs"
BOOK_DEPOSIT_DIR="/library/book_deposit"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project directories..."
mkdir -p $PROJECT_DIR

# --- 4. Create Application Files ---
echo "[+] Creating targeted_collector_v2.py application file..."
cat << 'EOF' > $PROJECT_DIR/targeted_collector_v2.py
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
MAX_WORKERS = 15
REST_PERIOD_SECONDS = 30
PAGES_TO_CRAWL = 3 # How many "Next" pages to follow in each collection

# --- List of Target URLs to Scrape ---
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
BASE_URL = "https://archive.org"

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'targeted_collector_v2.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def download_book(ebook_page_url):
    """Visits a final item page, finds the plain text link, and downloads the book."""
    try:
        # Check if the file already exists to avoid re-downloading
        title_from_url = ebook_page_url.split('/')[-1]
        sanitized_title = re.sub(r'[<>:"/\\|?*]', '_', title_from_url) + ".txt"
        if os.path.exists(os.path.join(BOOK_DEPOSIT_DIR, sanitized_title)):
            logging.info(f"Skipping already downloaded book: {sanitized_title}")
            return

        logging.info(f"Processing book page: {ebook_page_url}")
        response = requests.get(ebook_page_url, headers={'User-Agent': 'TargetedCollector/2.0'})
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'lxml')

        download_url = None
        text_link = soup.find('a', string=re.compile(r'FULL TEXT', re.IGNORECASE))
        if text_link:
            download_url = urljoin(ebook_page_url, text_link['href'])

        if not download_url:
            logging.warning(f"No plain text link found for {ebook_page_url}")
            return

        time.sleep(1) # Be respectful
        book_content_response = requests.get(download_url, headers={'User-Agent': 'TargetedCollector/2.0'})
        book_content_response.raise_for_status()

        title = soup.find('h1').text.strip() if soup.find('h1') else f"ebook_{int(time.time())}"
        filename = re.sub(r'[<>:"/\\|?*]', '_', title) + ".txt"
        output_path = os.path.join(BOOK_DEPOSIT_DIR, filename)
        
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(book_content_response.text)
        
        logging.info(f"Successfully downloaded: {filename}")

    except Exception as e:
        logging.error(f"Failed to download book from {ebook_page_url}: {e}", exc_info=True)

def crawl_collection(start_url):
    """Crawls a collection by following the 'Next' page links."""
    all_links = set()
    current_url = start_url
    
    for _ in range(PAGES_TO_CRAWL):
        try:
            logging.info(f"Crawling collection page: {current_url}")
            response = requests.get(current_url, headers={'User-Agent': 'TargetedCollector/2.0'})
            response.raise_for_status()
            soup = BeautifulSoup(response.text, 'lxml')
            
            # Find all direct item links on the current page
            page_links = {urljoin(current_url, a['href']) for a in soup.select('div.results-item a.title-link')}
            all_links.update(page_links)
            
            # Find the "Next" button to go to the next page
            next_page_link = soup.select_one('a.stealth.next-page')
            if next_page_link and next_page_link.has_attr('href'):
                current_url = urljoin(BASE_URL, next_page_link['href'])
                time.sleep(1) # Be respectful between page loads
            else:
                logging.info("No more pages found in this collection.")
                break
        except Exception as e:
            logging.error(f"Error crawling page {current_url}: {e}")
            break
            
    return list(all_links)

def main():
    while True:
        logging.info("--- Starting new Targeted Collector v2 cycle ---")
        
        all_links_to_process = set()
        for url in TARGET_URLS:
            found_links = crawl_collection(url)
            all_links_to_process.update(found_links)
        
        if all_links_to_process:
            unique_links = list(all_links_to_process)
            logging.info(f"Found a total of {len(unique_links)} unique ebook links to download.")
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                executor.map(download_book, unique_links)
        
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
sudo bash -c "cat << EOF > /etc/systemd/system/targeted_collector_v2.service
[Unit]
Description=Targeted Ebook Collector Service v2
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 targeted_collector_v2.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting Targeted Ebook Collector v2 service..."
sudo chown -R $USER:$USER /factory /library
sudo systemctl daemon-reload
sudo systemctl start targeted_collector_v2
sudo systemctl enable targeted_collector_v2

echo "--- Targeted Ebook Collector v2 Setup Complete ---"
echo "To check the status, run: sudo systemctl status targeted_collector_v2"
echo "To watch the logs, run: tail -f /factory/logs/targeted_collector_v2.log"
