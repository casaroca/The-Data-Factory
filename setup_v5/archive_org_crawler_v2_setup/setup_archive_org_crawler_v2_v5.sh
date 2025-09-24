#!/bin/bash
set -e

echo "--- Setting up Archive.org Crawler v2 v5 ---"

# --- 1. Stop and remove the old service to prevent conflicts ---
echo "[+] Stopping and removing old archive_org_crawler service..."
sudo systemctl stop archive_org_crawler_v2 || true
sudo systemctl disable archive_org_crawler_v2 || true
sudo rm -f /etc/systemd/system/archive_org_crawler_v2.service
sudo rm -rf /factory/workers/collectors/archive_org_crawler_v2
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/archive_org_crawler_v2_v5"
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
echo "[+] Creating archive_org_crawler_v2.py application file..."
cat << 'EOF' > $PROJECT_DIR/archive_org_crawler_v2.py
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
from selenium import webdriver
from selenium.webdriver.chrome.options import Options

# --- Configuration ---
LOG_DIR = "/factory/logs"
BOOK_DEPOSIT_DIR = "/library/book_deposit"
DATASET_DUMP_DIR = "/factory/data/raw/archive_org_datasets"
MAX_WORKERS = 10
REST_PERIOD_SECONDS = 25 # 25 second rest period
PAGES_TO_CRAWL = 3 # How many pages deep to go into listings

# Starting points for the crawl
START_URLS = [
    "https://archive.org/details/texts?sort=-publicdate",
    "https://archive.org/details/datasets?sort=-publicdate",
]
BASE_URL = "https://archive.org"

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'archive_org_crawler_v2.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def get_item_links_from_page(page_url):
    """Scrapes a listing page to find links to individual item pages."""
    all_links = set()
    current_url = page_url
    
    chrome_options = Options()
    chrome_options.add_argument("--headless")
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    driver = webdriver.Chrome(options=chrome_options)
    driver.execute_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")

    for page_num in range(PAGES_TO_CRAWL):
        try:
            logging.info(f"Fetching item list from page {page_num + 1}: {current_url}")
            driver.get(current_url)
            time.sleep(5) # wait for the page to load
            soup = BeautifulSoup(driver.page_source, 'lxml')
            
            # THE FIX: Updated CSS selector to match the new website structure.
            page_links = {BASE_URL + a['href'] for a in soup.select('div.item-tile > a')}
            if not page_links:
                logging.warning("No new links found on this page, stopping crawl for this source.")
                break
            
            all_links.update(page_links)
            
            # Find the "Next" button to go to the next page
            next_page_link = soup.select_one('a.stealth.next-page')
            if next_page_link and next_page_link.has_attr('href'):
                current_url = BASE_URL + next_page_link['href']
                time.sleep(1) # Be respectful between page loads
            else:
                logging.info("No more pages found for this source.")
                break
        except Exception as e:
            logging.error(f"Could not fetch item list from {current_url}: {e}")
            break
            
    driver.quit()
    return list(all_links)

def process_item_page(item_url):
    """Visits an item page and downloads the most relevant file."""
    try:
        logging.info(f"Processing item page: {item_url}")
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/115.0'
        }
        response = requests.get(item_url, headers=headers, timeout=60)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'lxml')

        download_link, file_type = None, None

        # Prioritization: Text > PDF > ZIP
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
        
        file_content_response = requests.get(download_link, timeout=600) # 10 min timeout for large files
        file_content_response.raise_for_status()

        title = soup.find('h1').text.strip()
        filename_base = re.sub(r'[<>:"/\\|?*]', '_', title)

        if file_type in ['txt', 'pdf']:
            filename = f"{filename_base}.{file_type}"
            output_path = os.path.join(BOOK_DEPOSIT_DIR, filename)
            with open(output_path, 'wb') as f:
                f.write(file_content_response.content)
            logging.info(f"Successfully downloaded book: {output_path}")
        
        elif file_type == 'zip':
            logging.info("Processing ZIP archive...")
            with zipfile.ZipFile(io.BytesIO(file_content_response.content)) as z:
                for member in z.namelist():
                    if member.lower().endswith(('.txt', '.csv', '.json', '.jsonl')):
                        z.extract(member, path=DATASET_DUMP_DIR)
                        logging.info(f"Extracted dataset file: {os.path.join(DATASET_DUMP_DIR, member)}")

    except Exception as e:
        logging.error(f"Failed to process item page {item_url}: {e}", exc_info=True)

def main():
    while True:
        logging.info("--- Starting new Archive.org Crawler cycle ---")
        
        all_item_links = []
        for start_url in START_URLS:
            all_item_links.extend(get_item_links_from_page(start_url))
        
        if all_item_links:
            items_to_process = random.sample(all_item_links, min(len(all_item_links), 10))
            logging.info(f"Selected {len(items_to_process)} items to process from the deep crawl.")
            
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                executor.map(process_item_page, items_to_process)
        
        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()
EOF

# --- 5. Create requirements.txt and Set Up Python Environment ---
echo "[+] Creating requirements.txt and setting up Python environment..."
cat << EOF > $PROJECT_DIR/requirements.txt
requests
beautifulsoup4
lxml
selenium
EOF
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/archive_org_crawler_v2_v5.service
[Unit]
Description=Archive.org Crawler Service v2 v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 archive_org_crawler_v2.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting Archive.org Crawler v2 service..."
sudo chown -R $USER:$USER /factory /library || true
sudo systemctl daemon-reload
sudo systemctl restart archive_org_crawler_v2_v5
sudo systemctl enable archive_org_crawler_v2_v5

echo "--- Archive.org Crawler v2 Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status archive_org_crawler_v2_v5"
echo "To watch the logs, run: tail -f /factory/logs/archive_org_crawler_v2.log"
