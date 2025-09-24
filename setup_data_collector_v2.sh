#!/bin/bash
set -e

echo "--- Setting up Data Collector v2 ---"

# --- 1. Stop and remove the old service to prevent conflicts ---
echo "[+] Stopping and removing old data_collector service..."
sudo systemctl stop data_collector || true
sudo systemctl disable data_collector || true
sudo rm -f /etc/systemd/system/data_collector.service
sudo rm -rf /factory/workers/collectors/data_collector
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/data_collector_v2"
LOG_DIR="/factory/logs"
DUMP_DIR="/factory/data/raw"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project directories..."
mkdir -p $PROJECT_DIR

# --- 4. Create Application Files ---
echo "[+] Creating data_collector_v2.py application file..."
cat << 'EOF' > $PROJECT_DIR/data_collector_v2.py
import os
import requests
import feedparser
import time
import logging
from concurrent.futures import ThreadPoolExecutor

# --- Configuration ---
LOG_DIR = "/factory/logs"
RAW_OUTPUT_DIR = "/factory/data/raw"
MAX_WORKERS = 25 # Increased from 20
REST_PERIOD_SECONDS = 60 # Decreased from 5 minutes

# Expanded list of high-quality business and finance sources
SOURCES=[
    {'url': 'https://feeds.harvard.edu/hbr', 'category': 'business'}, 
    {'url': 'https://www.wsj.com/xml/rss/3_7014.xml', 'category': 'finance'},
    {'url': 'https://www.economist.com/business/rss.xml', 'category': 'business'},
    {'url': 'http://feeds.reuters.com/reuters/businessNews', 'category': 'business'},
    {'url': 'https://www.forbes.com/business/feed/', 'category': 'business'},
    {'url': 'https://www.inc.com/rss/index.xml', 'category': 'business_startups'},
    {'url': 'https://www.entrepreneur.com/latest.rss', 'category': 'business_startups'},
    {'url': 'https://www.wired.com/feed/rss', 'category': 'tech_news'},
    {'url': 'https://arstechnica.com/feed/', 'category': 'tech_news'},
]

# --- Setup Logging ---
logging.basicConfig(filename=os.path.join(LOG_DIR,'data_collector_v2.log'), level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def dump_raw_content(content, source_category):
    try:
        dir_path = os.path.join(RAW_OUTPUT_DIR, source_category)
        os.makedirs(dir_path, exist_ok=True)
        filename = f"data_collector_v2_{int(time.time()*1000)}.html"
        filepath = os.path.join(dir_path, filename)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        logging.info(f"Dumped file to {filepath}")
    except Exception as e:
        logging.error(f"Failed to dump file for category {source_category}: {e}")

def scrape_rss_source(source):
    try:
        logging.info(f"Scraping RSS: {source['url']}")
        feed = feedparser.parse(source['url'])
        for entry in feed.entries[:5]:
            try:
                response = requests.get(entry.link, headers={'User-Agent': 'DataCollector/2.0'}, timeout=20)
                response.raise_for_status()
                dump_raw_content(response.text, source['category'])
            except Exception as e:
                logging.warning(f"Could not fetch article {entry.link}: {e}")
    except Exception as e:
        logging.error(f"Failed to parse RSS feed {source['url']}: {e}", exc_info=True)

def main():
    while True:
        logging.info("--- Starting new data_collector_v2 cycle ---")
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            for source in SOURCES:
                executor.submit(scrape_rss_source, source)
        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()
EOF

cat << 'EOF' > $PROJECT_DIR/requirements.txt
requests
feedparser
EOF

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/data_collector_v2.service
[Unit]
Description=Data Collector Service v2
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 data_collector_v2.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting Data Collector v2 service..."
sudo chown -R $USER:$USER /factory
sudo systemctl daemon-reload
sudo systemctl start data_collector_v2
sudo systemctl enable data_collector_v2

echo "--- Data Collector v2 Setup Complete ---"
echo "To check the status, run: sudo systemctl status data_collector_v2"
echo "To watch the logs, run: tail -f /factory/logs/data_collector_v2.log"
