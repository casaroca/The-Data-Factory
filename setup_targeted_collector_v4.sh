#!/bin/bash
set -e

echo "--- Setting up Targeted Ebook Collector v4 (Multi-Format) ---"

# --- 1. Stop and remove all old versions to prevent conflicts ---
echo "[+] Stopping and removing all old targeted_collector services..."
sudo systemctl stop targeted_collector targeted_collector_v2 targeted_collector_v3 || true
sudo systemctl disable targeted_collector targeted_collector_v2 targeted_collector_v3 || true
sudo rm -f /etc/systemd/system/targeted_collector.service
sudo rm -f /etc/systemd/system/targeted_collector_v2.service
sudo rm -f /etc/systemd/system/targeted_collector_v3.service
sudo rm -rf /factory/workers/collectors/targeted_collector
sudo rm -rf /factory/workers/collectors/targeted_collector_v2
sudo rm -rf /factory/workers/collectors/targeted_collector_v3
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/targeted_collector_v4"
LOG_DIR="/factory/logs"
BOOK_DEPOSIT_DIR="/library/book_deposit"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project directories..."
mkdir -p $PROJECT_DIR

# --- 4. Create Application Files ---
echo "[+] Creating targeted_collector_v4.py application file..."
cat << 'EOF' > $PROJECT_DIR/targeted_collector_v4.py
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
PAGES_TO_CRAWL = 3

TARGET_URLS = [
    "https://archive.org/details/cdl", "https://archive.org/details/umass_amherst_libraries",
    "https://archive.org/details/tischlibrary", "https://archive.org/details/delawarecountydistrictlibrary",
    "https://archive.org/details/computerworld", "https://archive.org/details/northeastern",
    "https://archive.org/details/dulua", "https://archive.org/details/mugar",
    "https://archive.org/details/aipi.ua-collection",
    "https://archive.org/details/texts?tab=collection&query=artificial+intelligence+llm",
    "https://archive.org/details/texts?tab=collection&query=llm"
]
BASE_URL = "https://archive.org"

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'targeted_collector_v4.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def download_book(ebook_page_url):
    try:
        logging.info(f"Processing book page: {ebook_page_url}")
        response = requests.get(ebook_page_url, headers={'User-Agent': 'TargetedCollector/4.0'})
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'lxml')

        # Prioritize download formats: TXT > PDF > EPUB > ZIP
        download_options = [
            ('txt', soup.find('a', string=re.compile(r'FULL TEXT', re.IGNORECASE))),
            ('pdf', soup.find('a', string=re.compile(r'PDF', re.IGNORECASE))),
            ('epub', soup.find('a', string=re.compile(r'EPUB', re.IGNORECASE))),
            ('zip', soup.find('a', string=re.compile(r'ZIP', re.IGNORECASE)))
        ]

        download_url, file_type = None, None
        for ftype, link in download_options:
            if link:
                download_url = urljoin(ebook_page_url, link['href'])
                file_type = ftype
                break

        if not download_url:
            logging.warning(f"No suitable download link found on {ebook_page_url}")
            return

        logging.info(f"Found {file_type.upper()} link: {download_url}")
        time.sleep(1)
        
        book_content_response = requests.get(download_url, headers={'User-Agent': 'TargetedCollector/4.0'})
        book_content_response.raise_for_status()

        title = soup.find('h1').text.strip() if soup.find('h1') else f"ebook_{int(time.time())}"
        filename = re.sub(r'[<>:"/\\|?*]', '_', title) + f".{file_type}"
        output_path = os.path.join(BOOK_DEPOSIT_DIR, filename)
        
        with open(output_path, 'wb') as f:
            f.write(book_content_response.content)
        
        logging.info(f"Successfully downloaded: {filename}")

    except Exception as e:
        logging.error(f"Failed to download book from {ebook_page_url}: {e}", exc_info=True)

def crawl_collection(start_url):
    all_links = set()
    current_url = start_url
    
    for _ in range(PAGES_TO_CRAWL):
        try:
            logging.info(f"Crawling collection page: {current_url}")
            response = requests.get(current_url, headers={'User-Agent': 'TargetedCollector/4.0'})
            response.raise_for_status()
            soup = BeautifulSoup(response.text, 'lxml')
            
            # This selector finds the links to the individual book/item pages
            page_links = {urljoin(current_url, a['href']) for a in soup.select('div.results-item a.title-link')}
            if not page_links:
                logging.warning(f"No item links found on {current_url}, stopping crawl for this source.")
                break
            
            all_links.update(page_links)
            
            next_page_link = soup.select_one('a.stealth.next-page')
            if next_page_link and next_page_link.has_attr('href'):
                current_url = urljoin(BASE_URL, next_page_link['href'])
                time.sleep(1)
            else:
                logging.info("No more pages found in this collection.")
                break
        except Exception as e:
            logging.error(f"Error crawling page {current_url}: {e}")
            break
            
    return list(all_links)

def main():
    while True:
        logging.info("--- Starting new Targeted Collector v4 cycle ---")
        
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
sudo bash -c "cat << EOF > /etc/systemd/system/targeted_collector_v4.service
[Unit]
Description=Targeted Ebook Collector Service v4
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 targeted_collector_v4.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting Targeted Ebook Collector v4 service..."
sudo chown -R $USER:$USER /factory /library
sudo systemctl daemon-reload
sudo systemctl start targeted_collector_v4
sudo systemctl enable targeted_collector_v4

echo "--- Targeted Ebook Collector v4 Setup Complete ---"
echo "To check the status, run: sudo systemctl status targeted_collector_v4"
echo "To watch the logs, run: tail -f /factory/logs/targeted_collector_v4.log"
