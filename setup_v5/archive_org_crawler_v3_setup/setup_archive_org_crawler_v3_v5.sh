#!/bin/bash
set -e

echo "--- Setting up Archive.org Crawler v3 (API-Powered) v5 ---"

# --- 1. Stop and remove ALL old versions to ensure a clean slate ---
echo "[+] Stopping and removing all old archive_org_crawler services..."
sudo systemctl stop archive_org_crawler archive_org_crawler_v2 archive_org_crawler_v3 || true
sudo systemctl disable archive_org_crawler archive_org_crawler_v2 archive_org_crawler_v3 || true
sudo rm -f /etc/systemd/system/archive_org_crawler.service
sudo rm -f /etc/systemd/system/archive_org_crawler_v2.service
sudo rm -f /etc/systemd/system/archive_org_crawler_v3.service
sudo rm -rf /factory/workers/collectors/archive_org_crawler
sudo rm -rf /factory/workers/collectors/archive_org_crawler_v2
sudo rm -rf /factory/workers/collectors/archive_org_crawler_v3
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/archive_org_crawler_v3_v5"
LOG_DIR="/factory/logs"
BOOK_DEPOSIT_DIR="/library/book_deposit"
DATASET_DUMP_DIR="/factory/data/raw/archive_org_datasets"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $BOOK_DEPOSIT_DIR
mkdir -p $DATASET_DUMP_DIR

# --- 4. Create Application Files ---
echo "[+] Creating archive_org_crawler_v3.py application file..."
cat << 'EOF' > $PROJECT_DIR/archive_org_crawler_v3.py
import os
import time
import logging
import requests
from bs4 import BeautifulSoup
import random
import re
import zipfile
import io
from concurrent.futures import ThreadPoolExecutor

# --- Configuration ---
LOG_DIR = "/factory/logs"
BOOK_DEPOSIT_DIR = "/library/book_deposit"
DATASET_DUMP_DIR = "/factory/data/raw/archive_org_datasets"
MAX_WORKERS = 15
REST_PERIOD_SECONDS = 30

# Keywords for targeted API queries
SEARCH_QUERIES = [
    "interpersonal skills", "etiquette", "generative ai", "language models",
    "vision models", "healthcare data", "finance fraud detection", "autonomous vehicles",
    "natural language processing", "sentiment analysis", "reinforcement learning",
    "time series data", "tabular data classification"
]
BASE_URL = "https://archive.org"
API_URL = "https://archive.org/advancedsearch.php"

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'archive_org_crawler_v3.log'), level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def get_item_identifiers_from_api(query):
    """Queries the Internet Archive API to get a list of item identifiers."""
    try:
        logging.info(f"Querying Archive.org API for: '{query}'")
        params = {
            'q': f'({query}) AND mediatype:(texts) AND publicdate:[2000-01-01 TO 2024-01-01]',
            'fl[]': 'identifier',
            'rows': '100',
            'output': 'json'
        }
        response = requests.get(API_URL, params=params, headers={'User-Agent': 'ArchiveCrawler/3.0'})
        response.raise_for_status()
        data = response.json()
        
        docs = data.get('response', {}).get('docs', [])
        identifiers = [doc['identifier'] for doc in docs]
        logging.info(f"API returned {len(identifiers)} results for query '{query}'.")
        return identifiers
    except Exception as e:
        logging.error(f"Could not query API for '{query}': {e}")
        return []

def process_item(identifier):
    """Visits an item page by its identifier and downloads the most relevant file."""
    item_url = f"{BASE_URL}/details/{identifier}"
    try:
        logging.info(f"Processing item page: {item_url}")
        response = requests.get(item_url, headers={'User-Agent': 'ArchiveCrawler/3.0'}, timeout=60)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'lxml')

        download_link, file_type = None, None

        txt_link = soup.find('a', string=re.compile(r'FULL TEXT', re.IGNORECASE))
        pdf_link = soup.find('a', string=re.compile(r'PDF', re.IGNORECASE))
        zip_link = soup.find('a', string=re.compile(r'ZIP', re.IGNORECASE))

        if txt_link:
            download_link, file_type = BASE_URL + txt_link['href'], 'txt'
        elif pdf_link:
            download_link, file_type = BASE_URL + pdf_link['href'], 'pdf'
        elif zip_link:
            download_link, file_type = BASE_URL + zip_link['href'], 'zip'

        if not download_link:
            logging.warning(f"No suitable download link found on {item_url}")
            return

        logging.info(f"Found {file_type} link: {download_link}")
        time.sleep(2)
        
        file_content_response = requests.get(download_link, timeout=600)
        file_content_response.raise_for_status()

        title = soup.find('h1').text.strip()
        filename_base = re.sub(r'[<>:"/\\|?*]', '_', title)

        if file_type == 'zip':
            logging.info("Inspecting ZIP archive...")
            zip_file = zipfile.ZipFile(io.BytesIO(file_content_response.content))
            is_dataset = any(member.lower().endswith(('.txt', '.csv', '.json', '.jsonl')) for member in zip_file.namelist())
            
            if is_dataset:
                logging.info("Dataset found. Extracting text-based files...")
                for member in zip_file.namelist():
                    if member.lower().endswith(('.txt', '.csv', '.json', '.jsonl')):
                        zip_file.extract(member, path=DATASET_DUMP_DIR)
                        logging.info(f"Extracted dataset file: {os.path.join(DATASET_DUMP_DIR, member)}) 
            else:
                logging.info("ZIP is not a dataset. Saving as a book.")
                filename = f"{filename_base}.zip"
                output_path = os.path.join(BOOK_DEPOSIT_DIR, filename)
                with open(output_path, 'wb') as f:
                    f.write(file_content_response.content)
                logging.info(f"Successfully downloaded book archive: {output_path}")
        else:
            filename = f"{filename_base}.{file_type}"
            output_path = os.path.join(BOOK_DEPOSIT_DIR, filename)
            with open(output_path, 'wb') as f:
                f.write(file_content_response.content)
            logging.info(f"Successfully downloaded book: {output_path}")

    except Exception as e:
        logging.error(f"Failed to process item {identifier}: {e}", exc_info=True)

def main():
    while True:
        logging.info("--- Starting new Archive.org Crawler v3 cycle ---")
        
        query = random.choice(SEARCH_QUERIES)
        item_ids = get_item_identifiers_from_api(query)
        
        if item_ids:
            items_to_process = random.sample(item_ids, min(len(item_ids), 10))
            logging.info(f"Selected {len(items_to_process)} items to process from API query.")
            
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                executor.map(process_item, items_to_process)
        
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
sudo bash -c "cat << EOF > /etc/systemd/system/archive_org_crawler_v3_v5.service
[Unit]
Description=Archive.org Crawler Service v3 v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 archive_org_crawler_v3.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting Archive.org Crawler v3 service..."
sudo chown -R $USER:$USER /factory /library
sudo systemctl daemon-reload
sudo systemctl start archive_org_crawler_v3_v5
sudo systemctl enable archive_org_crawler_v3_v5

echo "--- Archive.org Crawler v3 Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status archive_org_crawler_v3_v5"
echo "To watch the logs, run: tail -f /factory/logs/archive_org_crawler_v3.log"
