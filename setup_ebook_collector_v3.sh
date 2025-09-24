#!/bin/bash
set -e

echo "--- Setting up Ebook Collector v3 ---"

# --- 1. Stop and remove the old service to prevent conflicts ---
echo "[+] Stopping and removing old ebook_collector_v2 service..."
sudo systemctl stop ebook_collector_v2 || true
sudo systemctl disable ebook_collector_v2 || true
sudo rm -f /etc/systemd/system/ebook_collector_v2.service
sudo rm -rf /factory/workers/collectors/ebook_collector_v2
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/ebook_collector_v3"
LOG_DIR="/factory/logs"
DEPOSIT_DIR="/factory/library/book_deposit"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project directories..."
mkdir -p $PROJECT_DIR

# --- 4. Create Application Files ---
echo "[+] Creating ebook_collector_v3.py application file..."
cat << 'EOF' > $PROJECT_DIR/ebook_collector_v3.py
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
DEPOSIT_DIR = "/factory/library/book_deposit"
MAX_WORKERS = 15
REST_PERIOD_SECONDS = 60

# Expanded list of public domain ebook sources
SOURCES = {
    "gutenberg": {"list_url": "https://www.gutenberg.org/browse/scores/top"},
    "standard_ebooks": {"list_url": "https://standardebooks.org/ebooks"},
    "internet_archive": {"list_url": "https://archive.org/details/texts?sort=-publicdate"},
    "hathitrust": {"list_url": "https://babel.hathitrust.org/cgi/mb?a=listis;c=1495534215"},
    "feedbooks": {"list_url": "http://www.feedbooks.com/publicdomain"}
}

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'ebook_collector_v3.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def get_ebook_links(source_name, config):
    try:
        logging.info(f"Fetching ebook list from: {source_name}")
        response = requests.get(config['list_url'], headers={'User-Agent': 'EbookCollector/3.0'})
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'lxml')
        links = set()
        
        if source_name == "gutenberg":
            links.update(urljoin(config['list_url'], a['href']) for a in soup.find_all('a') if a.get('href', '').startswith('/ebooks/'))
        elif source_name == "standard_ebooks":
            links.update(a['href'] for a in soup.select('li.ebook-entry > a'))
        elif source_name == "internet_archive":
            links.update(urljoin(config['list_url'], a['href']) for a in soup.select('div.item-tile > a'))
        elif source_name == "hathitrust":
            links.update(a['href'] for a in soup.select('a[href*="handle.net"]'))
        elif source_name == "feedbooks":
            links.update(urljoin(config['list_url'], a['href']) for a in soup.select('a.book-title'))

        return list(links)
    except Exception as e:
        logging.error(f"Could not fetch ebook list from {source_name}: {e}")
        return []

def download_book(ebook_page_url):
    try:
        logging.info(f"Processing book page: {ebook_page_url}")
        response = requests.get(ebook_page_url, headers={'User-Agent': 'EbookCollector/3.0'})
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'lxml')

        download_url, file_type = None, None
        
        # Prioritize EPUB then PDF
        epub_link = soup.find('a', href=re.compile(r'\.epub', re.IGNORECASE))
        pdf_link = soup.find('a', href=re.compile(r'\.pdf', re.IGNORECASE))

        if epub_link:
            download_url, file_type = urljoin(ebook_page_url, epub_link['href']), 'epub'
        elif pdf_link:
            download_url, file_type = urljoin(ebook_page_url, pdf_link['href']), 'pdf'

        if not download_url:
            logging.warning(f"No EPUB or PDF link found for {ebook_page_url}")
            return

        time.sleep(1)
        book_content_response = requests.get(download_url, headers={'User-Agent': 'EbookCollector/3.0'})
        book_content_response.raise_for_status()

        title = soup.find('h1').text.strip() if soup.find('h1') else f"ebook_{int(time.time())}"
        filename = re.sub(r'[<>:"/\\|?*]', '_', title) + f".{file_type}"
        output_path = os.path.join(DEPOSIT_DIR, filename)
        
        with open(output_path, 'wb') as f:
            f.write(book_content_response.content)
        
        logging.info(f"Successfully downloaded: {filename}")

    except Exception as e:
        logging.error(f"Failed to download book from {ebook_page_url}: {e}", exc_info=True)

def main():
    while True:
        logging.info("--- Starting new Ebook Collector v3 cycle ---")
        
        all_links = []
        for name, config in SOURCES.items():
            all_links.extend(get_ebook_links(name, config))
        
        if all_links:
            books_to_download = random.sample(all_links, min(len(all_links), 15))
            logging.info(f"Selected {len(books_to_download)} books for this cycle.")
            
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                executor.map(download_book, books_to_download)
        
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
sudo bash -c "cat << EOF > /etc/systemd/system/ebook_collector_v3.service
[Unit]
Description=Ebook Collector Service v3
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 ebook_collector_v3.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting Ebook Collector v3 service..."
sudo chown -R $USER:$USER /factory /library
sudo systemctl daemon-reload
sudo systemctl start ebook_collector_v3
sudo systemctl enable ebook_collector_v3

echo "--- Ebook Collector v3 Setup Complete ---"
echo "To check the status, run: sudo systemctl status ebook_collector_v3"
echo "To watch the logs, run: tail -f /factory/logs/ebook_collector_v3.log"
