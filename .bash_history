sudo apt update && sudo apt install nano -y && sudo apt install ufw -y
ip a
lsblk
nano setup_foundation.sh
chmod +x setup_foundation.sh
sudo ./setup_foundation.sh
nano setup_librarian.sh
chmod +x setup_librarian.sh
sudo ./setup_librarian.sh
ip a
nano setup_librarian.sh
chmod +x setup_librarian.sh
nano setup_librarian.sh
sudo ./setup_librarian.sh
# Find the filename
ls /etc/netplan/
# Open the file (replace the filename if it's different from 50-cloud-init.yaml)
sudo nano /etc/netplan/50-cloud-init.yaml
sudo netplan apply
ip a
nano setup_librarian.sh
sudo ./setup_librarian.sh
sudo systemctl status librarian
sudo apt update && sudo apt install -y libfontconfig1
sudo systemctl restart librarian
sudo apt install -y libxkbcommon0
sudo systemctl restart librarian
sudo systemctl status librarian
nano setup_jr_librarian.sh
chmod +x setup_jr_librarian_v2.sh
nano setup_jr_librarian.sh
chmod +x setup_jr_librarian_v2.sh
sudo ./setup_jr_librarian_v2.sh
nano setup_jr_librarian_v2.sh
chmod +x setup_jr_librarian_v2.sh
sudo ./setup_jr_librarian_v2.sh
nano setup_jr_librarian_v2.sh
chmod +x setup_jr_librarian_v2.sh
sudo ./setup_jr_librarian_v2.sh
To watch the logs, run: tail -f /factory/logs/jr_librarian.log
tail -f /factory/logs/jr_librarian.log
nano
nano language_collector_v2
chmod +x language_collector_v2
sudo ./language_collector_v2
nano tech_collector_v2
chmod +x tech_collector_v2
sudo ./tech_collector_v2
tail -f /factory/logs/tech_collector_v2.log
nano business_collector_v2
chmod +x business_collector_v2
sudo ./business_collector_v2
nano stats_collector_v2
chmod +x #!/bin/bash
set -e
echo "--- Setting up Stats Collector v2 ---"
# --- 1. Stop and remove the old service to prevent conflicts ---
echo "[+] Stopping and removing old stats_collector service..."
sudo systemctl stop stats_collector || true
sudo systemctl disable stats_collector || true
sudo rm -f /etc/systemd/system/stats_collector.service
sudo rm -rf /factory/workers/collectors/stats_collector
sudo systemctl daemon-reload
# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/stats_collector_v2"
LOG_DIR="/factory/logs"
DUMP_DIR="/factory/data/raw"
USER="tdf"
# --- 3. Create Directories ---
echo "[+] Creating project directories..."
mkdir -p $PROJECT_DIR
# --- 4. Create Application Files ---
echo "[+] Creating stats_collector_v2.py application file..."
cat << 'EOF' > $PROJECT_DIR/stats_collector_v2.py
import os
import requests
import time
import logging
import json
import feedparser
from concurrent.futures import ThreadPoolExecutor

# --- Configuration ---
LOG_DIR = "/factory/logs"
RAW_OUTPUT_DIR = "/factory/data/raw"
MAX_WORKERS = 30 # Increased for the larger number of sources
REST_PERIOD_SECONDS = 60 # 1 minute rest period

# Expanded list of North American statistical sources
SOURCES = {
    'apis': [
        # Mexico
        {'name': 'INEGI Mexico Inflation', 'url': 'https://www.inegi.org.mx/app/api/indicadores/desarrolladores/jsonxml/INDICATOR/6207062288/es/0700/false/BIE/2.0/82dd1ae5-8a1b-4c52-8832-b45192267bf6?type=json', 'category': 'stats_inegi_mx_inflation'},
        {'name': 'Mexico Balance of Payments', 'url': 'http://api.worldbank.org/v2/country/MX/indicator/BN.CAB.XOKA.CD?format=json', 'category': 'stats_worldbank_mx_bop'},
        # USA
        {'name': 'US Unemployment', 'url': 'https://api.bls.gov/publicAPI/v2/timeseries/data/LNS14000000', 'category': 'stats_bls_us_unemployment'},
        # Note: FRED API requires a free API key. This will be skipped gracefully if not set.
        {'name': 'US GDP', 'url': 'https://api.stlouisfed.org/fred/series/observations?series_id=GDP&api_key=YOUR_FRED_API_KEY&file_type=json', 'category': 'stats_fred_us_gdp'}, 
        # Canada
        {'name': 'Bank of Canada Interest Rate', 'url': 'https://www.bankofcanada.ca/valet/observations/V122513/json', 'category': 'stats_boc_ca_interest'},
    ],
    'rss_feeds': [
        {'url': 'https://open.canada.ca/data/en/feeds/dataset.atom', 'category': 'gov_canada_data'},
        {'url': 'https://www.data.gov/feed.xml', 'category': 'gov_usa_data'},
        {'url': 'https://datos.gob.mx/feed.xml', 'category': 'gov_mexico_data'},
    ]
}

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    filename=os.path.join(LOG_DIR, 'stats_collector_v2.log'),
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logging.getLogger('').addHandler(logging.StreamHandler())

def dump_raw_content(content, source_category, extension):
    try:
        dir_path = os.path.join(RAW_OUTPUT_DIR, source_category)
        os.makedirs(dir_path, exist_ok=True)
        filename = f"stats_collector_v2_{int(time.time() * 1000)}.{extension}"
        filepath = os.path.join(dir_path, filename)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        logging.info(f"Dumped file to {filepath}")
    except Exception as e:
        logging.error(f"Failed to dump file for {source_category}: {e}")

def scrape_api_source(source):
    try:
        logging.info(f"Querying API: {source['name']}")
        if 'YOUR_FRED_API_KEY' in source['url']:
            logging.warning("FRED API key not set. Skipping US GDP source. Get a free key at https://fred.stlouisfed.org/")
            return
        response = requests.get(source['url'], timeout=30)
        response.raise_for_status()
        dump_raw_content(response.text, source['category'], 'json')
    except Exception as e:
        logging.error(f"Failed to query {source['name']}: {e}", exc_info=True)

def scrape_rss_source(source):
    try:
        logging.info(f"Querying RSS: {source['url']}")
        feed = feedparser.parse(source['url'], agent='StatsCollector/2.0')
        for entry in feed.entries[:3]: # Get top 3 entries from data portals
            try:
                # We are interested in the metadata page, not necessarily the raw file link
                dump_raw_content(str(entry), source['category'], 'txt')
            except Exception:
                pass
    except Exception as e:
        logging.error(f"Failed to parse RSS feed {source['url']}: {e}", exc_info=True)

def main():
    while True:
        logging.info("--- Starting new Stats Collector v2 cycle ---")
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            for source in SOURCES['apis']:
                executor.submit(scrape_api_source, source)
            for source in SOURCES['rss_feeds']:
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
sudo bash -c "cat << EOF > /etc/systemd/system/stats_collector_v2.service
[Unit]
Description=Stats Collector Service v2
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 stats_collector_v2.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"
# --- 7. Start the Service ---
echo "[+] Starting Stats Collector v2 service..."
sudo chown -R $USER:$USER /factory
sudo systemctl daemon-reload
sudo systemctl start stats_collector_v2
sudo systemctl enable stats_collector_v2
echo "--- Stats Collector v2 Setup Complete ---"
echo "To check the status, run: sudo systemctl status stats_collector_v2"
echo "To watch the logs, run: tail -f /factory/logs/stats_collector_v2.log"
nano info_collector_v2
chmod +x info_collector_v2
sudo ./info_collector_v2
nano ebook_collector_v2
chmod +x ebook_collector_v2
sudo ./ebook_collector_v2
nano ebook_collector_v2
chmod +x ebook_collector_v2
sudo ./ebook_collector_v2
tail -f /factory/logs/ebook_collector_v2.log
nano nypl_collector
chmod +x #!/bin/bash
set -e
echo "--- Setting up NYPL Collector ---"
# --- 1. Define Absolute Paths ---
PROJECT_DIR="/factory/workers/collectors/nypl_collector"
LOG_DIR="/factory/logs"
DUMP_DIR="/factory/data/raw/nypl_api"
USER="tdf"
# --- 2. Create Project Directory ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $DUMP_DIR
# --- 3. Create Application Files ---
echo "[+] Creating NYPL Collector application files..."
cat << 'EOF' > $PROJECT_DIR/nypl_collector.py
import os
import requests
import time
import logging
import json
import random
from concurrent.futures import ThreadPoolExecutor

# --- Configuration ---
LOG_DIR = "/factory/logs"
RAW_OUTPUT_DIR = "/factory/data/raw/nypl_api"
API_TOKEN = "gc1o02f9dvyplx4j"
SEARCH_TERMS = ["history", "science", "new york", "maps", "manuscripts", "photography", "art", "literature", "letters", "diaries"]
REST_PERIOD_SECONDS = 60 # 1 minute rest period
MAX_WORKERS = 5

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    filename=os.path.join(LOG_DIR, 'nypl_collector.log'),
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logging.getLogger('').addHandler(logging.StreamHandler())

def dump_raw_content(content, query_term):
    try:
        dir_path = os.path.join(RAW_OUTPUT_DIR, query_term)
        os.makedirs(dir_path, exist_ok=True)
        filename = f"nypl_{query_term}_{int(time.time() * 1000)}.json"
        filepath = os.path.join(dir_path, filename)
        with open(filepath, 'w', encoding='utf-8') as f:
            json.dump(content, f, indent=2, ensure_ascii=False)
        logging.info(f"Dumped file to {filepath}")
    except Exception as e:
        logging.error(f"Failed to dump file for query '{query_term}': {e}")

def scrape_nypl_api(query_term):
    """Searches the NYPL API for a given term and downloads the results."""
    try:
        logging.info(f"Querying NYPL API for '{query_term}'...")
        url = f"https://api.repo.nypl.org/api/v2/items/search?q={query_term}&publicDomainOnly=true&per_page=100"
        headers = {"Authorization": f"Token token=\"{API_TOKEN}\""}
        
        response = requests.get(url, headers=headers, timeout=45)
        response.raise_for_status()
        data = response.json()
        
        results = data.get('nyplAPI', {}).get('response', {}).get('result', [])
        if results:
            dump_raw_content(results, query_term)
        else:
            logging.warning(f"No results found for '{query_term}'")

    except Exception as e:
        logging.error(f"Failed to query NYPL API for '{query_term}': {e}", exc_info=True)

def main():
    while True:
        logging.info("--- Starting new NYPL Collector cycle ---")
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            # Query 3 random terms per cycle to vary the data
            selected_terms = random.sample(SEARCH_TERMS, min(len(SEARCH_TERMS), 3))
            for term in selected_terms:
                executor.submit(scrape_nypl_api, term)
        
        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()
EOF

cat << 'EOF' > $PROJECT_DIR/requirements.txt
requests
EOF

# --- 4. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt
# --- 5. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/nypl_collector.service
[Unit]
Description=NYPL Collector Service
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 nypl_collector.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"
# --- 6. Start the Service ---
echo "[+] Starting NYPL Collector service..."
sudo chown -R $USER:$USER /factory
sudo systemctl daemon-reload
sudo systemctl start nypl_collector
sudo systemctl enable nypl_collector
echo "--- NYPL Collector Setup Complete ---"
echo "To check the status, run: sudo systemctl status nypl_collector"
echo "To watch the logs, run: tail -f /factory/logs/nypl_collector.log"
nano ebook_collector_v2
sudo chown -R $USER:$USER /factory /library
sudo systemctl daemon-reload
sudo systemctl start ebook_collector_v3
sudo systemctl enable ebook_collector_v3
sudo chown -R $USER:$USER /factory /library
nano ebook_collector_v2
nano ebook_collector_v3
sudo systemctl enable ebook_collector_v3
nano ebook_collector_v2
sudo chown -R $USER:$USER /factory /library
sudo systemctl daemon-reload
sudo systemctl start ebook_collector_v3
sudo systemctl enable ebook_collector_v3
sudo systemctl enable ebook_collector_v2
sudo systemctl start ebook_collector_v2
tail -f /factory/logs/ebook_collector_v2.log
nano topic_puller
sudo systemctl daemon-reload
sudo systemctl start topic_puller
sudo systemctl enable topic_puller
sudo systemctl daemon-reload
sudo systemctl start topic_puller
sudo systemctl enable topic_puller
nano topic_puller
sudo systemctl enable topic_puller
nano topic_puller
chmod +x setup_topic_puller.sh
nano topic_puller
chmod +x setup_topic_puller.sh
sudo ./setup_topic_puller.sh
tail -f /factory/logs/topic_puller.log
nano youtube_transcriber
chmod +x setup_youtube_transcriber.sh
sudo chown -R $USER:$USER /factory
chmod +x setup_youtube_transcriber.sh
nano youtube_transcriber.sh
nano youtube_transcriber
chmod +x setup_youtube_transcriber.sh
sudo ./setup_youtube_transcriber.sh
tail -f /factory/logs/youtube_transcriber.log
nano setup_youtube_transcriber
nano youtube_transcriber.sh
nano setup_youtube_transcriber.sh
chmod +x setup_youtube_transcriber.sh
sudo ./setup_youtube_transcriber.sh
tail -f /factory/logs/youtube_transcriber.log
nano setup_youtube_transcriber.sh
chmod +x setup_youtube_transcriber.sh
sudo ./setup_youtube_transcriber.sh
tail -f /factory/logs/youtube_transcriber.log
nano setup_youtube_transcriber.sh
chmod +x setup_youtube_transcriber_v3.sh
nano setup_youtube_transcriber.sh
chmod +x setup_youtube_transcriber_v3.sh
sudo ./setup_youtube_transcriber_v3.sh
tail -f $LOG_DIR/youtube_transcriber_v3.log
tail -f /factory/logs/youtube_transcriber_v3.log
/factory/logs/youtube_transcriber_v3.log
sudo journalctl -u youtube_transcriber_v3 -f -n 100
nano setup_youtube_transcriber.sh
sudo journalctl -u youtube_transcriber_v3 -f -n 100
sudo systemctl status youtube_transcriber_v3.service
sudo journalctl -u youtube_transcriber_v3 -n 50 --no-pager
nano setup_data_collector_v2.sh
chmod +x setup_data_collector_v2.sh
sudo ./setup_data_collector_v2.sh
nano setup_archive_org_crawler_v1.sh
chmod +x setup_archive_org_crawler_v1.sh
sudo ./setup_archive_org_crawler_v1.sh
nano setup_archive_org_crawler_v1.sh
chmod +x setup_archive_org_crawler_v1.sh
sudo ./setup_archive_org_crawler_v1.sh
chmod +x setup_archive_org_crawler_v2.sh
sudo ./setup_archive_org_crawler_v1.sh
nano setup_archive_org_crawler_v1.sh
chmod +x setup_archive_org_crawler_v2.sh
chmod +x setup_archive_org_crawler_v1.sh
sudo ./setup_archive_org_crawler_v1.sh
nano setup_archive_org_crawler_v1.sh
chmod +x setup_archive_org_crawler_v1.sh
sudo ./setup_archive_org_crawler_v1.sh
tail -f /factory/logs/archive_org_crawler_v2.log
tail -f /factory/logs/archive_org_crawler_v1.log
tail -f /factory/logs/archive_org_crawler_v2.log
nano setup_archive_org_crawler_v1.sh
[A
nano setup_archive_org_crawler_v1.sh
chmod +x setup_archive_org_crawler_v1.sh
sudo ./setup_archive_org_crawler_v1.sh
nano setup_archive_org_crawler_v1.sh
chmod +x setup_archive_org_crawler_v3.sh
sudo ./setup_archive_org_crawler_v3.sh
tail -f /factory/logs/archive_org_crawler_v3.log
nano setup_archive_org_crawler_v3.sh
chmod +x setup_archive_org_crawler_v3.sh
sudo ./setup_archive_org_crawler_v3.sh
tail -f /factory/logs/archive_org_crawler_v3.log
nano setup_archive_org_crawler_v3.sh
chmod +x setup_archive_org_crawler_v3.sh
sudo ./setup_archive_org_crawler_v3.sh
tail -f /factory/logs/archive_org_crawler_v3.log
nano setup_archive_org_crawler_v3.sh
chmod +x setup_archive_org_crawler_v3.sh
sudo ./setup_archive_org_crawler_v3.sh
tail -f /factory/logs/archive_org_crawler_v3.log
nano setup_targeted_collector.sh
chmod +x setup_targeted_collector.sh
sudo ./setup_targeted_collector.sh
tail -f /factory/logs/targeted_collector.log
nano setup_targeted_collector_v2.sh
chmod +x setup_targeted_collector_v2.sh
sudo ./setup_targeted_collector_v2.sh
tail -f /factory/logs/targeted_collector_v2.log
nano setup_targeted_collector_v2.sh
chmod +x setup_targeted_collector_v2.sh
sudo ./setup_targeted_collector_v2.sh
tail -f /factory/logs/targeted_collector_v2.log
nano setup_targeted_collector_v2.sh
chmod +x setup_targeted_collector_v2.sh
sudo ./setup_targeted_collector_v2.sh
tail -f /factory/logs/targeted_collector_v2.log
nano setup_targeted_collector_v3.sh
chmod +x setup_targeted_collector_v3.sh
sudo ./setup_targeted_collector_v3.sh
nano setup_targeted_collector_v3.sh
chmod +x setup_targeted_collector_v4.sh
sudo ./setup_targeted_collector_v4.sh
tail -f /factory/logs/targeted_collector_v4.log
nano setup_targeted_collector_v3.sh
nano setup_targeted_collector_v4.sh
chmod +x setup_targeted_collector_v4.sh
sudo ./setup_targeted_collector_v4.sh
tail -f /factory/logs/targeted_collector_v4.log
nano setup_targeted_collector_v5.sh
chmod +x setup_targeted_collector_v5.sh
sudo ./setup_targeted_collector_v5.sh
tail -f /factory/logs/targeted_collector_v5.log
nano setup_targeted_collector_v6.sh
chmod +x setup_targeted_collector_v6.sh
sudo ./setup_targeted_collector_v6.sh
nano setup_archive_org_query_collector.sh
chmod +x setup_archive_org_query_collector.sh
sudo ./setup_archive_org_query_collector.sh
nano setup_common_crawl_query_collector.sh
chmod +x setup_common_crawl_query_collector.sh
sudo ./setup_common_crawl_query_collector.sh
tail -f /factory/logs/common_crawl_query_collector.log
nano setup_common_crawl_query_collector.sh
chmod +x setup_common_crawl_query_collector.sh
sudo ./setup_common_crawl_query_collector.sh
tail -f /factory/logs/common_crawl_query_collector.log
nano setup_common_crawl_query_collector.sh
chmod +x setup_common_crawl_query_collector.sh
sudo ./setup_common_crawl_query_collector.sh
tail -f /factory/logs/common_crawl_query_collector.log
nano setup_common_crawl_bulk_collector.sh
chmod +x setup_common_crawl_bulk_collector.sh
sudo ./setup_common_crawl_bulk_collector.sh
tail -f /factory/logs/common_crawl_bulk_collector.log
nano setup_common_crawl_bulk_collector.sh
chmod +x setup_common_crawl_bulk_collector.sh
sudo ./setup_common_crawl_bulk_collector.sh
tail -f /factory/logs/common_crawl_bulk_collector.log
nano setup_common_crawl_bulk_collector.sh
chmod +x setup_common_crawl_bulk_collector.sh
sudo ./setup_common_crawl_bulk_collector.sh
tail -f /factory/logs/common_crawl_bulk_collector.log
nano setup_common_crawl_bulk_collector.sh
chmod +x setup_common_crawl_bulk_collector.sh
sudo ./setup_common_crawl_bulk_collector.sh
tail -f /factory/logs/common_crawl_bulk_collector.log
nano setup_common_crawl_bulk_collector.sh
chmod +x setup_common_crawl_bulk_collector.sh
sudo ./setup_common_crawl_bulk_collector.sh
tail -f /factory/logs/common_crawl_bulk_collector.log
# Stop and disable the service
sudo systemctl stop common_crawl_bulk_collector
sudo systemctl disable common_crawl_bulk_collector
# Remove the service configuration file
sudo rm /etc/systemd/system/common_crawl_bulk_collector.service
# Reload systemd to clear it from memory
sudo systemctl daemon-reload
# Remove the project directory
sudo rm -rf /factory/workers/collectors/common_crawl_bulk_collector
echo "Common Crawl Bulk Collector has been completely removed."
sqlite3 /factory/db/library.db "SELECT count(*) FROM books WHERE processed_by_topic_puller = 0;"
nano setup_common_crawl_harvester.sh
chmod +x setup_common_crawl_harvester.sh
sudo ./setup_common_crawl_harvester.sh
tail -f /factory/logs/common_crawl_harvester.log
nano setup_common_crawl_harvester.sh
chmod +x setup_common_crawl_harvester.sh
sudo ./setup_common_crawl_harvester.sh
tail -f /factory/logs/common_crawl_harvester.log
nano setup_common_crawl_harvester.sh
chmod +x setup_common_crawl_harvester.sh
sudo ./setup_common_crawl_harvester.sh
tail -f /factory/logs/common_crawl_harvester.log
nano setup_common_crawl_harvester.sh
chmod +x setup_common_crawl_harvester.sh
sudo ./setup_common_crawl_harvester.sh
tail -f /factory/logs/common_crawl_harvester.log
nano setup_common_crawl_harvester.sh
chmod +x setup_common_crawl_harvester_v2.sh
sudo ./setup_common_crawl_harvester_v2.sh
tail -f /factory/logs/common_crawl_harvester_v2.log
nano setup_common_crawl_harvester.sh
chmod +x setup_common_crawl_harvester_v2.sh
sudo ./setup_common_crawl_harvester_v2.sh
tail -f /factory/logs/common_crawl_harvester_v2.log
sudo systemctl status common_crawl_harvester_v2
tail -f /factory/logs/common_crawl_harvester_v2.log
sudo journalctl -u ebook_collector_v3 -n 50 --no-pager
sudo journalctl -u ebook_collector_v2 -n 50 --no-pager
sudo journalctl -u ebook_collector_v2 -n 50 
sudo journalctl -u ebook_collector_v2 
tail -f /factory/logs/ebook_collector_v2.log
sudo apt install htop
htop
nano setup_youtube_transcriber.sh
sudo systemctl stop youtube_transcriber_v3.service
nano youtube_transcriber_v3.service
nano setup_youtube_transcriber.shchmod +x setup_youtube_transcriber.sh
sudo ./setup_youtube_transcriber.sh
chmod +x setup_youtube_transcriber.sh
sudo ./setup_youtube_transcriber.sh
sudo systemctl status youtube_transcriber_v3.service
sudo ./setup_youtube_transcriber.sh
tail -f /factory/logs/youtube_transcriber_v3.log
/factory/logs/youtube_transcriber_v3.log
tail -f /factory/logs/youtube_transcriber.log
nano setup_youtube_transcriber.sh
chmod +x setup_youtube_transcriber.sh
sudo ./setup_youtube_transcriber.sh
tail -f /factory/logs/youtube_transcriber.log
sudo systemctl stop youtube_transcriber.service || true
sudo systemctl stop youtube_transcriber_v3.service || true
pkill -f youtube_transcriber.py || true
grep -Rni "get_transcript" /factory/workers/extractors/youtube_transcriber || true
sudo systemctl stop youtube_transcriber.service || true
sudo systemctl stop youtube_transcriber_v3.service || true
pkill -f youtube_transcriber.py || true
nano setup_youtube_transcriber.sh
# Add your ID to the list (one per line)
echo "GJLlxj_dtq8" | sudo tee -a /etc/youtube_transcriber/videos.txt
# Start and verify the path it’s running from (look for RUNNING FROM line)
sudo systemctl daemon-reload
sudo systemctl start youtube_transcriber.service
sudo systemctl status youtube_transcriber.service --no-pager
tail -n 100 /factory/logs/youtube_transcriber.log
sudo systemctl daemon-reload
sudo systemctl start youtube_transcriber.service
sudo systemctl status youtube_transcriber.service --no-pager
tail -n 100 /factory/logs/youtube_transcriber.log
# enter the service venv
source /factory/workers/extractors/youtube_transcriber/venv/bin/activate
python - <<'PY'
import sys, inspect
import youtube_transcript_api
from youtube_transcript_api import YouTubeTranscriptApi
try:
    import youtube_transcript_api._version as _v
    ver = getattr(_v, "__version__", "unknown")
except Exception:
    ver = "unknown"

print("python:", sys.version)
print("module file:", youtube_transcript_api.__file__)
print("package path:", youtube_transcript_api.__path__ if hasattr(youtube_transcript_api, "__path__") else "n/a")
print("version:", ver)
print("has get_transcript:", hasattr(YouTubeTranscriptApi, "get_transcript"))
print("has list_transcripts:", hasattr(YouTubeTranscriptApi, "list_transcripts"))
PY

deactivate
source /factory/workers/extractors/youtube_transcriber/venv/bin/activate
# What does pip think is installed?
pip show youtube-transcript-api
# What files are actually in the installed package?
python - <<'PY'
import os, pkgutil, inspect, youtube_transcript_api
from pathlib import Path
print("pkg:", youtube_transcript_api.__file__)
p = Path(youtube_transcript_api.__file__).parent
print("contents:", sorted(os.listdir(p)))
print("__init__.py head:")
print(Path(p/"__init__.py").read_text(encoding="utf-8")[:400])
PY

nano setup_youtube_transcriber.sh
sudo systemctl daemon-reload
sudo systemctl restart youtube_transcriber.service
tail -n 200 -f /factory/logs/youtube_transcriber.log
systemctl cat youtube_transcriber.service
nano setup_youtube_transcriber.sh
grep -nE 'list_transcripts|get_transcript|_errors' "$APP" || echo "OK: app uses instance API only"
source /factory/workers/extractors/youtube_transcriber/venv/bin/activate
python - <<'PY'
from youtube_transcript_api import YouTubeTranscriptApi
ytt = YouTubeTranscriptApi()
print("instance has .list:", hasattr(ytt, "list"))
print("instance has .fetch:", hasattr(ytt, "fetch"))
PY

deactivate
sudo nano /etc/systemd/system/youtube_transcriber.service
# Make sure ExecStart is exactly one line:
# ExecStart=/factory/workers/extractors/youtube_transcriber/venv/bin/python3 /factory/workers/extractors/youtube_transcriber/youtube_transcriber.py
sudo systemctl daemon-reload
sudo systemctl restart youtube_transcriber.service
sudo systemctl status youtube_transcriber.service --no-pager
nano setup_youtube_transcriber.sh
pgrep -a -f youtube_transcriber.py
ps -p $(pgrep -n -f youtube_transcriber.py) -o args=
sudo sed -n '1,80p' /factory/workers/extractors/youtube_transcriber/youtube_transcriber.py
nano setup_youtube_transcriber.sh
sudo sed -i 's|^ExecStart=.*|ExecStart=/factory/workers/extractors/youtube_transcriber/venv/bin/python3 /factory/workers/extractors/youtube_transcriber/youtube_transcriber.py|' "$UNIT"
sudo systemctl daemon-reload
sudo systemctl restart youtube_transcriber.service
sudo systemctl status youtube_transcriber.service --no-pager
tail -n 200 -f /factory/logs/youtube_transcriber.log
nano setup_youtube_transcriber.sh
sudo systemctl daemon-reload
sudo systemctl restart youtube_transcriber.service
sudo systemctl status youtube_transcriber.service --no-pager
nano setup_advanced_monitor_v2.sh
chmod +x setup_advanced_monitor_v2.sh
sudo ./setup_advanced_monitor_v2.sh
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
nano setup_advanced_monitor_v2.sh
[A
nano setup_advanced_monitor_v2.sh
chmod +x setup_advanced_monitor_v3.sh
sudo ./setup_advanced_monitor_v3.sh
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
nano setup_advanced_monitor_v2.sh
nano setup_advanced_monitor_v3.sh
chmod +x setup_advanced_monitor_v3.sh
sudo ./setup_advanced_monitor_v3.sh
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
nano setup_advanced_monitor_v4.sh
chmod +x setup_advanced_monitor_v4.sh
sudo ./setup_advanced_monitor_v4.sh
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
nano setup_advanced_monitor_v4.sh
chmod +x setup_advanced_monitor_v4.sh
sudo ./setup_advanced_monitor_v4.sh
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
ip a
sudo nano /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
sudo netplan apply
ls /etc/netplan/
nano 50-cloud-init.yaml
ip a
sudo nano /etc/netplan/50-cloud-init.yaml
sudo netplan apply
nano setup_social_media_scraper.sh
chmod +x setup_social_media_scraper.sh
sudo ./setup_social_media_scraper.sh
nano setup_social_media_scraper.sh
chmod +x setup_social_media_scraper.sh
sudo ./setup_social_media_scraper.sh
nano setup_social_media_scraper.sh
chmod +x setup_social_media_scraper.sh
nano setup_social_media_scraper.sh
sudo ./setup_social_media_scraper.sh
tail -f /factory/logs/social_media_scraper.log
ip a
tail -f /factory/logs/social_media_scraper.log
nano setup_youtube_crawler_v1.sh
nano setup_youtube_transcriber.sh
chmod +x setup_youtube_transcriber.sh
sudo ./setup_youtube_transcriber.sh
nano setup_youtube_transcriber_v2.sh
chmod +x setup_youtube_transcriber_v2.sh
sudo ./setup_youtube_transcriber_v2.sh
nano setup_youtube_transcriber_v2.sh
chmod +x setup_youtube_transcriber_v2.sh
sudo ./setup_youtube_transcriber_v2.sh
tail -f /factory/logs/youtube_transcriber.log
nano setup_youtube_transcriber_v2.sh
chmod +x setup_youtube_transcriber_v2.sh
nano setup_youtube_transcriber_v2.sh
chmod +x setup_youtube_transcriber_v2.sh
sudo ./setup_youtube_transcriber_v2.sh
tail -f /factory/logs/youtube_transcriber.log
nano setup_youtube_transcriber_v2.sh
chmod +x setup_youtube_transcriber_v2.sh
sudo ./setup_youtube_transcriber_v2.sh
tail -f /factory/logs/youtube_transcriber.log
nano setup_youtube_transcriber_v2.sh
chmod +x setup_youtube_transcriber_v2.sh
sudo ./setup_youtube_transcriber_v2.sh
tail -f /factory/logs/youtube_transcriber.log
nano setup_youtube_transcriber_v2.sh
chmod +x setup_youtube_transcriber_v2.sh
sudo ./setup_youtube_transcriber_v2.sh
tail -f /factory/logs/youtube_transcriber.log
nano setup_youtube_transcriber_v2.sh
chmod +x setup_youtube_transcriber_v2.sh
sudo ./setup_youtube_transcriber_v2.sh
tail -f /factory/logs/youtube_transcriber.log
nano setup_youtube_transcriber_v2.sh
chmod +x setup_youtube_transcriber_v2.sh
sudo ./setup_youtube_transcriber_v2.sh
tail -f /factory/logs/youtube_transcriber.log
nano setup_youtube_transcriber_v2.sh
chmod +x setup_youtube_transcriber_v2.sh
sudo ./setup_youtube_transcriber_v2.sh
tail -f /factory/logs/youtube_transcriber.log
nano setup_youtube_transcriber_v2.sh
chmod +x setup_youtube_transcriber_v2.sh
sudo ./setup_youtube_transcriber_v2.sh
tail -f /factory/logs/youtube_transcriber.log
nano setup_youtube_transcriber_v2.sh
chmod +x setup_youtube_transcriber_v3.sh
sudo ./setup_youtube_transcriber_v3.sh
tail -f /factory/logs/youtube_transcriber_v3.log
tail -f /factory/logs/youtube_transcriber.log
nano setup_youtube_transcriber_v2.sh
chmod +x setup_youtube_transcriber_v3.sh
sudo ./setup_youtube_transcriber_v3.sh
tail -f /factory/logs/youtube_transcriber.log
nano setup_youtube_transcriber_v2.sh
chmod +x setup_youtube_transcriber_v3.sh
sudo ./setup_youtube_transcriber_v3.sh
tail -f /factory/logs/youtube_transcriber.log
nano setup_youtube_transcriber_v2.sh
nano setup_youtube_transcriber_v3.sh
chmod +x setup_youtube_transcriber_v3.sh
sudo ./setup_youtube_transcriber_v3.sh
nano setup_youtube_transcriber_v3.sh
chmod +x setup_youtube_transcriber_v3.sh
sudo ./setup_youtube_transcriber_v3.sh
nano setup_youtube_transcriber_v3.sh
chmod +x setup_youtube_transcriber_v3.sh
sudo ./setup_youtube_transcriber_v3.sh
tail -f /factory/logs/youtube_transcriber.log
#!/bin/bash
set -e
echo "--- Setting up YouTube Transcriber v3 (Final Version) ---"
# --- 1. Stop and remove all old versions to prevent conflicts ---
echo "[+] Stopping and removing all old youtube_transcriber services..."
sudo systemctl stop youtube_transcriber || true
sudo systemctl disable youtube_transcriber || true
sudo rm -f /etc/systemd/system/youtube_transcriber.service
sudo rm -rf /factory/workers/extractors/youtube_transcriber
sudo systemctl daemon-reload
# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/extractors/youtube_transcriber"
LOG_DIR="/factory/logs"
DUMP_DIR="/factory/data/raw/youtube_transcripts"
USER="tdf"
# --- 3. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $DUMP_DIR
# --- 4. Create Application Files ---
echo "[+] Creating youtube_transcriber.py application file..."
cat << 'EOF' > $PROJECT_DIR/youtube_transcriber.py
import os
import time
import json
from datetime import datetime, timedelta
import requests
from youtube_transcript_api import YouTubeTranscriptApi
from youtube_transcript_api._errors import TranscriptsDisabled, NoTranscriptFound, VideoUnavailable
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
import re
import logging
import random
from concurrent.futures import ThreadPoolExecutor

# --- Configuration ---
LOG_DIR = "/factory/logs"
RAW_OUTPUT_DIR = "/factory/data/raw/youtube_transcripts"
API_KEY = "AIzaSyBhT9dvKiq379NkRO3TAJkJZCIykvACe4Y"
MAX_WORKERS = 2 # Reduced workers for less aggressive polling
REST_PERIOD_SECONDS = 60 * 60 # Increased rest period to 1 hour to manage quota

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'youtube_transcriber.log'), level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logging.getLogger('googleapiclient.discovery_cache').setLevel(logging.ERROR)
logging.getLogger('').addHandler(logging.StreamHandler())

class YouTubeTranscriptCrawler:
    def __init__(self, api_key):
        self.youtube = build('youtube', 'v3', developerKey=api_key)
        self.search_queries = [
            "social media marketing tutorial", "AI training tutorial", "machine learning course",
            "digital marketing guide", "social media strategy tutorial", "artificial intelligence training",
            "deep learning tutorial", "facebook ads tutorial", "instagram marketing guide",
            "youtube marketing tutorial", "AI automation tutorial", "chatbot training",
            "content marketing tutorial", "SEO tutorial", "email marketing course"
        ]

    def search_educational_videos(self, query, max_results=3, days_back=30): # Reduced from 10 to 3
        try:
            published_after = (datetime.now() - timedelta(days=days_back)).isoformat() + 'Z'
            search_response = self.youtube.search().list(
                q=query + ' tutorial OR course OR guide OR training',
                part='id,snippet', maxResults=max_results, type='video',
                publishedAfter=published_after, order='relevance', videoDuration='medium'
            ).execute()
            
            videos = []
            educational_keywords = ['tutorial', 'course', 'guide', 'training', 'learn', 'how to', 'beginner', 'advanced', 'step by step', 'explained', 'basics']
            for item in search_response.get('items', []):
                snippet = item.get('snippet', {})
                if not snippet: continue
                title = snippet.get('title', '').lower()
                description = snippet.get('description', '').lower()
                if any(keyword in title or keyword in description for keyword in educational_keywords):
                    videos.append({
                        'video_id': item.get('id', {}).get('videoId'), 'title': snippet.get('title'),
                        'description': snippet.get('description'), 'channel': snippet.get('channelTitle'),
                        'published_at': snippet.get('publishedAt'), 'search_query': query
                    })
            return videos
        except HttpError as e:
            if e.resp.status == 403:
                logging.warning(f"Quota exceeded while searching for '{query}'. Pausing for a longer duration.")
                # If we hit a quota error, sleep for an extra hour.
                time.sleep(3600)
            else:
                logging.error(f"An HTTP error occurred while searching for '{query}': {e}")
            return []

    def get_transcript(self, video_id, languages=['en']):
        transcript_data = None
        try:
            transcript_list = YouTubeTranscriptApi.list_transcripts(video_id)
            for transcript in transcript_list:
                if transcript.language_code in languages:
                    transcript_data = transcript.fetch()
                    break
            if not transcript_data:
                transcript_data = transcript_list.find_transcript(languages).fetch()

            if not transcript_data:
                return None

            full_text = ' '.join([item['text'] for item in transcript_data])
            full_text = re.sub(r'\[.*?\]', '', full_text)
            full_text = re.sub(r'\s+', ' ', full_text).strip()
            return full_text

        except (TranscriptsDisabled, VideoUnavailable, NoTranscriptFound):
            logging.warning(f"No transcript available for video {video_id}")
            return None
        except Exception as e:
            logging.error(f"Could not retrieve transcript for {video_id}: {str(e)}")
            return None

    def crawl_and_save(self, query):
        logging.info(f"Processing query: '{query}'")
        videos = self.search_educational_videos(query, max_results=3) # Reduced from 5 to 3
        if not videos:
            logging.info(f"No relevant videos found for query: {query}")
            return

        successful_count = 0
        for video in videos:
            video_id = video.get('video_id')
            if not video_id: continue
            
            title_preview = video.get('title', 'N/A')[:50]
            transcript = self.get_transcript(video_id)
            if transcript and len(transcript.strip()) > 100:
                result = {**video, 'transcript': transcript, 'crawled_at': datetime.now().isoformat()}
                
                filename = f"youtube_{video_id}.json"
                filepath = os.path.join(RAW_OUTPUT_DIR, filename)
                with open(filepath, 'w', encoding='utf-8') as f:
                    json.dump(result, f, indent=2, ensure_ascii=False)
                successful_count += 1
                logging.info(f"✓ Saved transcript for '{title_preview}...'")
            else:
                logging.warning(f"✗ No valid transcript for '{title_preview}...'")
            time.sleep(2)
        logging.info(f"Query '{query}' completed: {successful_count}/{len(videos)} transcripts extracted.")

def main():
    try:
        crawler = YouTubeTranscriptCrawler(API_KEY)
    except Exception as e:
        logging.error(f"Failed to initialize crawler: {e}")
        return

    while True:
        logging.info("--- Starting new YouTube Crawler cycle ---")
        # Process only one query per cycle to be very conservative with the API quota
        query_to_run = random.choice(crawler.search_queries)
        
        crawler.crawl_and_save(query_to_run)
            
        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()
EOF

cat << 'EOF' > $PROJECT_DIR/requirements.txt
google-api-python-client
youtube-transcript-api
requests
EOF

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
rm -rf $PROJECT_DIR/venv
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt
nano setup_advanced_monitor_v4.sh
chmod +x setup_advanced_monitor_v4.sh
sudo ./setup_advanced_monitor_v4.sh
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
nano setup_advanced_monitor_v4.sh
chmod +x setup_advanced_monitor_v4.sh
sudo ./setup_advanced_monitor_v4.sh
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
nano setup_advanced_monitor_v4.sh
chmod +x setup_advanced_monitor_v4.sh
sudo ./setup_advanced_monitor_v4.sh
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
nano setup_advanced_monitor_v6.sh
chmod +x setup_advanced_monitor_v6.sh
sudo ./setup_advanced_monitor_v6.sh
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
nano setup_advanced_monitor_v6.sh
chmod +x setup_advanced_monitor_v6.sh
sudo ./setup_advanced_monitor_v6.sh
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
0;35;8M0;35;8mtdf
htop
nano setup_youtube_transcriber_v3.sh
chmod +x setup_youtube_transcriber_v3.sh
sudo ./setup_youtube_transcriber_v3.sh
tail -f /factory/logs/youtube_transcriber.log
sudo systemctl stop youtube_transcriber
tail -f /factory/logs/youtube_transcriber.log
sudo systemctl stop youtube_transcriber
sudo systemctl stop youtube_transcriber_v3
tail -f /factory/logs/common_crawl_harvester.log
nano setup_archive_org_harvester.sh
chmod +x setup_archive_org_harvester.sh
sudo ./setup_archive_org_harvester.sh
tail -f /factory/logs/archive_org_harvester.log
nano setup_archive_org_harvester.sh
chmod +x setup_archive_org_harvester.sh
nano setup_archive_org_harvester.sh
nano setup_archive_org_harvester_v2.sh
chmod +x setup_archive_org_harvester_v2.sh
sudo ./setup_archive_org_harvester_v2.sh
tail -f /factory/logs/archive_org_harvester_v2.log
nano setup_archive_org_harvester_v2.sh
chmod +x setup_archive_org_harvester_v2.sh
sudo ./setup_archive_org_harvester_v2.sh
tail -f /factory/logs/archive_org_harvester_v2.log
nano setup_archive_org_harvester_v2.sh
chmod +x setup_archive_org_harvester_v2.sh
sudo ./setup_archive_org_harvester_v2.sh
tail -f /factory/logs/archive_org_harvester_v2.log
nano setup_archive_org_harvester_v2.sh
chmod +x setup_archive_org_harvester_v2.sh
sudo ./setup_archive_org_harvester_v2.sh
tail -f /factory/logs/archive_org_harvester_v2.log
nano setup_archive_org_harvester_v2.sh
chmod +x setup_archive_org_harvester_v2.sh
sudo ./setup_archive_org_harvester_v2.sh
tail -f /factory/logs/archive_org_harvester_v2.log
nano setup_archive_org_harvester_v2.sh
chmod +x setup_archive_org_harvester_v2.sh
sudo ./setup_archive_org_harvester_v2.sh
nano setup_arxiv_harvester.sh
chmod +x setup_arxiv_harvester.sh
sudo ./setup_arxiv_harvester.sh
tail -f /factory/logs/arxiv_harvester.log
nano setup_arxiv_harvester.sh
chmod +x setup_arxiv_harvester.sh
sudo ./setup_arxiv_harvester.sh
tail -f /factory/logs/arxiv_harvester.log
nano setup_arxiv_harvester.sh
chmod +x setup_arxiv_harvester.sh
sudo ./setup_arxiv_harvester.sh
tail -f /factory/logs/arxiv_harvester.log
nano setup_arxiv_harvester.sh
chmod +x setup_arxiv_harvester.sh
sudo ./setup_arxiv_harvester.sh
tail -f /factory/logs/arxiv_harvester.log
nano setup_arxiv_harvester_v3.sh
chmod +x setup_arxiv_harvester_v3.sh
sudo ./setup_arxiv_harvester_v3.sh
tail -f /factory/logs/arxiv_harvester_v3.log
sudo apt update && sudo apt install speedtest-cli
speedtest-cli
nano setup_dpla_harvester.sh
chmod +x setup_dpla_harvester.sh
sudo ./setup_dpla_harvester.sh
tail -f /factory/logs/dpla_harvester.log
nano setup_dpla_harvester.sh
chmod +x setup_dpla_harvester.sh
sudo ./setup_dpla_harvester.sh
tail -f /factory/logs/dpla_harvester.log
nano setup_dpla_harvester.sh
chmod +x setup_dpla_harvester.sh
sudo ./setup_dpla_harvester.sh
tail -f /factory/logs/dpla_harvester.log
nano setup_dpla_harvester.sh
chmod +x setup_dpla_harvester.sh
sudo ./setup_dpla_harvester.sh
tail -f /factory/logs/dpla_harvester.log
nano setup_dpla_harvester.sh
chmod +x setup_dpla_harvester.sh
sudo ./setup_dpla_harvester.sh
tail -f /factory/logs/dpla_harvester.log
nano setup_dpla_harvester.sh
chmod +x setup_dpla_harvester.sh
sudo ./setup_dpla_harvester.sh
tail -f /factory/logs/dpla_harvester.log
sudo ./setup_dpla_harvester.sh
sudo systemctl stop dpla_harvester
sudo nano /factory/workers/collectors/dpla_harvester/dpla_harvester.py
sudo systemctl start dpla_harvester
tail -f /factory/logs/dpla_harvester.log
nano setup_dpla_harvester.sh
chmod +x setup_dpla_harvester.sh
sudo ./setup_dpla_harvester.sh
tail -f /factory/logs/dpla_harvester.log
nano setup_public_dataset_harvester.sh
chmod +x setup_public_dataset_harvester.sh
sudo ./setup_public_dataset_harvester.sh
tail -f /factory/logs/public_dataset_harvester.log
nano setup_public_dataset_harvester.sh
chmod +x setup_public_dataset_harvester.sh
sudo ./setup_public_dataset_harvester.sh
tail -f /factory/logs/public_dataset_harvester.log
nano setup_public_dataset_harvester.sh
sudo systemctl status public_dataset_harvester_v2
chmod +x setup_public_dataset_harvester.sh
sudo ./setup_public_dataset_harvester.sh
tail -f /factory/logs/public_dataset_harvester_v2.log
nano setup_public_dataset_harvester.sh
chmod +x setup_public_dataset_harvester.sh
sudo ./setup_public_dataset_harvester.sh
tail -f /factory/logs/public_dataset_harvester_v2.log
nano setup_public_dataset_harvester.sh
chmod +x setup_public_dataset_harvester.sh
sudo ./setup_public_dataset_harvester.sh
tail -f /factory/logs/public_dataset_harvester_v2.log
nano setup_public_dataset_harvester.sh
chmod +x setup_public_dataset_harvester.sh
sudo ./setup_public_dataset_harvester.sh
tail -f /factory/logs/public_dataset_harvester_v2.log
nano setup_public_dataset_harvester.sh
chmod +x setup_public_dataset_harvester.sh
sudo ./setup_public_dataset_harvester.sh
tail -f /factory/logs/public_dataset_harvester_v2.log
nano setup_ebook_collector_v3.sh
chmod +x setup_ebook_collector_v3.sh
sudo ./setup_ebook_collector_v3.sh
tail -f /factory/logs/ebook_collector_v3.log
nano setup_common_crawl_harvester_v3.sh
chmod +x setup_common_crawl_harvester_v3.sh
sudo ./setup_common_crawl_harvester_v3.sh
tail -f /factory/logs/common_crawl_harvester_v3.log
ip a 
nano setup_common_crawl_bulk_collector.sh
ip a 
cat /etc/netplan/50-cloud-init.yaml
nano  /etc/netplan/50-cloud-init.yaml
nano setup_big_harvester_monitor.sh
chmod +x setup_big_harvester_monitor.sh
sudo ./setup_big_harvester_monitor.sh
watch -n 10 /factory/workers/collectors/big_harvester_v1/monitor.sh
watch -n 10 /factory/workers/collectors/big_harvester_v1/monitor.sh
htop
ip a
fsck -y /dev/sdb1
cat /etc/netplan.50-cloud-init.yaml
cat /etc/netplan/50-cloud-init.yaml
sudo cat /etc/netplan.50-cloud-init.yaml
sudo cat /etc/netplan/50-cloud-init.yaml
sudo systemctlrestart systemd-networkd
sudo systemctl restart systemd-networkd
ip a
sudo systemctl restart systemd-networkd
ip a
sudo systemctl restart systemd-networkd
ip a
sudo systemctl disable systemd-networkd-wait-online.service
reboot
ip a
echo "network: {config: disabled}" | sudo tee /etc/cloud/cloud.cfg.d/99-disabl-network-config.cfg
sudo systemctl disable systemd-networkd-wait-online.service
sudo reboot
ip a
sudo apt-get purge cloud-init -y
sudo reboot
ip a
sudo netplan generate
nano  /etc/netplan/50-cloud-init.yaml
nano /etc/netplan/50-cloud-init.yaml
sudo nano /etc/netplan/50-cloud-init.yaml
sudo netplan apply 
sudo reboot
ip a
dir
ip a
sudo touch /forcefsck
sudo reboot
journalctl -p 0..4 -b
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
glances
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
tail -f /factory/logs/fdlp_harvester.log
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
sudo systemctl status fdlp_harvester
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
tail -f /factory/logs/fdlp_harvester.log
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
tail -f /factory/logs/fdlp_harvester.log
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
tail -f /factory/logs/fdlp_harvester.log
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
tail -f /factory/logs/fdlp_harvester.log
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
tail -f /factory/logs/fdlp_harvester.log
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
systemctl status fdlp_harvester2.service
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
systemctl status fdlp_harvester2.service
systemctl status fdlp_harvester2.service.
systemctl status fdlp_harvester2.service
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
tail -f /factory/logs/fdlp_harvester.log
sudo systemctl restart fdlp_harvester
tail -f /factory/logs/fdlp_harvester.log
systemctl status fdlp_harvester2.service
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
tail -f /factory/logs/fdlp_harvester.log
systemctl status fdlp_harvester2.service
tail -f /factory/logs/fdlp_harvester.log
sudo systemctl restart fdlp_harvester
tail -f /factory/logs/fdlp_harvester.log
systemctl status fdlp_harvester2.service
tail -f /factory/logs/fdlp_harvester.log
systemctl status fdlp_harvester2.service
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
tail -f /factory/logs/fdlp_harvester.log
nano setup_fdlp_harvester.sh
chmod +x setup_fdlp_harvester.sh
sudo ./setup_fdlp_harvester.sh
tail -f /factory/logs/fdlp_harvester.log
nano setup_data_transporter_v1.sh
chmod +x setup_data_transporter_v1.sh
sudo ./setup_data_transporter_v1.sh
nano setup_advanced_monitor_v7.sh
chmod +x setup_advanced_monitor_v7.sh
sudo ./setup_advanced_monitor_v7.sh
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
glances
nano setup_archiver.sh
chmod +x setup_archiver.sh
sudo ./setup_archiver.sh
nano setup_archiver.sh
chmod +x setup_archiver.sh
sudo ./setup_archiver.sh
nano setup_archiver.sh
chmod +x setup_archiver.sh
sudo ./setup_archiver.sh
nano setup_archiver.sh
chmod +x setup_archiver.sh
sudo ./setup_archiver.sh
nano setup_archiver.sh
chmod +x setup_archiver.sh
sudo ./setup_archiver.sh
sudo systemctl start archiver
tail -f /factory/logs/archiver.log
chmod +x setup_archiver.sh
nano setup_archiver.sh
chmod +x setup_archiver.sh
sudo ./setup_archiver.sh
tail -f /factory/logs/archiver.log
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
chmod +x setup_topic_puller_v2.sh
nano setup_topic_puller_v2.sh
chmod +x setup_topic_puller_v2.sh
sudo ./setup_topic_puller_v2.sh
nano setup_topic_puller_v2.sh
chmod +x setup_topic_puller_v2.sh
sudo ./setup_topic_puller_v2.sh
nano setup_topic_puller_v2.sh
chmod +x setup_topic_puller_v2.sh
sudo ./setup_topic_puller_v2.sh
tail -f /factory/logs/topic_puller.log
nano setup_topic_puller_v2.sh
sudo ./setup_topic_puller_v2.sh
tail -f /factory/logs/topic_puller.log
nano setup_topic_puller_v2.sh
chmod +x setup_topic_puller_v2.sh
sudo ./setup_topic_puller_v2.sh
tail -f /factory/logs/topic_puller.log
# A. Add TEMPORARY extra swap right now (prevents OOM while you fix)
sudo fallocate -l 8G /swapfile2
sudo chmod 600 /swapfile2
sudo mkswap /swapfile2
sudo swapon /swapfile2
# B. Nudge the kernel to avoid eager swapping (persists after next step)
echo vm.swappiness=10 | sudo tee /etc/sysctl.d/90-swap-tuning.conf
sudo sysctl --system
# C. Soft-throttle noisy workers while you investigate (lower priority + IO priority)
sudo renice +10 -p $(pgrep -f 'data_factory|collector|processor|archiver' | tr '\n' ' ')
sudo ionice -c2 -n7 -p $(pgrep -f 'data_factory|collector|processor|archiver' | tr '\n' ' ')
# Top RAM hogs (RSS) and SWAP per process
ps -eo pid,comm,rss --sort=-rss | head -n 20
sudo bash -c 'for p in /proc/[0-9]*; do pid=${p##*/}; swp=$(grep -i ^VmSwap $p/status 2>/dev/null|awk "{print \$2}"); [ "${swp:-0}" -gt 0 ] && printf "%10s %12s KB %s\n" "$pid" "$swp" "$(tr -d "\0" < $p/cmdline)"; done | sort -k2 -nr | head -n 20'
# Realtime IO pressure (per disk & per process)
iostat -xz 1 5
pidstat -d 1 5
dstat -cdm --top-io 5
# Or: atop and press d (disk), m (mem)
sudo apt-get update && sudo apt-get install -y zram-tools || sudo apt-get install -y systemd-zram-generator
nano setup_ethical_sorter.sh
chmod +x setup_ethical_sorter.sh
sudo ./setup_ethical_sorter.sh
nano setup_ethical_sorter.sh
sudo ./setup_ethical_sorter.sh
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
glances
htop
nano setup_discard_processor.sh
chmod +x setup_discard_processor.sh
sudo ./setup_discard_processor.sh
nano setup_data_processor.sh
chmod +x setup_data_processor.sh
sudo ./setup_data_processor.sh
tail -f /factory/logs/data_processor.log
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
tail -f /factory/logs/ethical_sorter.log
htop
glances
htop
tail -f /factory/logs/discard_processor.log
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
nano setup_jr_librarian_v2.sh
chmod +x setup_jr_librarian_v2.sh
sudo ./setup_jr_librarian_v2.sh
nano setup_jr_librarian_v2.sh
chmod +x setup_jr_librarian_v2.sh
sudo ./setup_jr_librarian_v2.sh
tail -f /factory/logs/jr_librarian.log
nano setup_jr_librarian_v2.sh
chmod +x setup_jr_librarian_v2.sh
sudo ./setup_jr_librarian_v2.sh
tail -f /factory/logs/jr_librarian.log
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
nano setup_advanced_monitor_v7.sh
chmod +x setup_advanced_monitor_v7.sh
sudo ./setup_advanced_monitor_v7.sh
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
nano setup_advanced_monitor_v7.sh
chmod +x setup_advanced_monitor_v7.sh
sudo ./setup_advanced_monitor_v7.sh
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
nano setup_advanced_monitor_v7.sh
chmod +x setup_advanced_monitor_v7.sh
sudo ./setup_advanced_monitor_v7.sh
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
nano setup_advanced_monitor_v7.sh
sudo ./setup_advanced_monitor_v7.sh
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
nano setup_image_processor.sh
chmod +x setup_image_processor.sh
sudo ./setup_image_processor.sh
tail -f /factory/logs/image_processor.log
sudo systemctl status image_processor
# generate en_CA.UTF-8
sudo apt-get update && sudo apt-get install -y locales
echo "en_CA.UTF-8 UTF-8" | sudo tee -a /etc/locale.gen
sudo locale-gen
sudo update-locale LANG=en_CA.UTF-8 LC_ALL=en_CA.UTF-8
# on TDF (new SSH session)
locale | egrep 'LANG|LC_ALL'
cat /etc/default/locale
localectl status 2>/dev/null || true
sudo sed -i '/source "\$ENV_FILE"/a export SRC_DIR DEST_HOST DEST_PATH LOG_FILE EXCLUDES ALLOW_DELETE_ON_DEST BWLIMIT_KBPS RSYNC_EXTRA SSH_KEY PASSWORD LOW_SPACE_TRIGGER_GB MAX_RUN_MINUTES LOOP_SLEEP_SEC'   /factory/workers/transfer/transfer_worker_v3/bin/transfer_worker_v3.sh
sudo chmod +x /factory/workers/transfer/transfer_worker_v3/bin/transfer_worker_v3.sh
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
tail -f /factory/logs/data_processor.log
nano setup_salvage_extractor.sh
chmod +x setup_salvage_extractor.sh
sudo ./setup_salvage_extractor.sh
nano setup_salvage_extractor.sh
chmod +x setup_salvage_extractor.sh
sudo ./setup_salvage_extractor.sh
tail -f /factory/logs/salvage_extractor.log
nano setup_data_packager.sh
chmod +x setup_data_packager.sh
sudo ./setup_data_packager.sh
nano setup_data_packager.sh
chmod +x setup_data_packager.sh
sudo ./setup_data_packager.sh
tail -f /factory/logs/data_packager.log
chmod +x setup_image_processor.sh
sudo ./setup_image_processor.sh
tail -f /factory/logs/data_packager.log
/factory/workers/monitors/advanced_monitor/advanced_monitor.shsudo systemctl start bulk_txt_extractor.service
sudo systemctl start bulk_txt_extractor.service
ls -l /factory/workers/bulk_txt_extractor/bin/bulk_txt_extractor.sh
extract_all.py
sudo extract_all.py
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
nano /factory/scripts/file_transfer.sh
sudo nano /factory/scripts/file_transfer.sh
md /factory/scripts/
sudo md /factory/scripts/
nano /factory/scripts/file_transfer.sh
nano /factory/workers/file_transfer.sh
chmod +x /factory/workers/file_transfer.sh
sudo apt-get update
sudo apt-get install -y poppler-utils pandoc tesseract-ocr python3 python3-pip
pip3 install PyPDF2 beautifulsoup4 python-docx openpyxl pillow pytesseract
sudo ln -s /factory/workers/file_transfer.sh /usr/local/bin/factory-transfer
./factory/workers/file_transfer.sh setup
sudo ./factory/workers/file_transfer.sh setup
nano /factory/workers/file_transfer.sh
sudo mkdir -p /factory/workers
sudo nano /factory/workers/file_transfer.sh
sudo chmod +x /factory/workers/file_transfer.sh
sudo chown tdf:tdf /factory/workers/file_transfer.sh
ls -la /factory/workers/file_transfer.sh
/factory/workers/file_transfer.sh
sudo /factory/workers/file_transfer.sh setup
/factory/workers/file_transfer.sh tail
/factory/workers/file_transfer.sh status
tail -f /factory/logs/file_transfer.log
cp /factory/workers/file_transfer.sh /factory/workers/file_transfer.sh.backup
nano /factory/workers/file_transfer.sh
# First, scan to see what will be processed (with verbose to see depth info)
/factory/workers/file_transfer.sh scan --verbose
# Then process everything (this will take a while!)
/factory/workers/file_transfer.sh process
# Monitor progress in another terminal
/factory/workers/file_transfer.sh tail
/factory/workers/file_transfer.sh service install
/factory/workers/file_transfer.sh service enable
/factory/workers/file_transfer.sh status
/factory/workers/file_transfer.sh monitor
/factory/workers/file_transfer.sh logs
/factory/workers/file_transfer.sh tail
/factory/workers/file_transfer.sh monitor
tail -f /factory/logs/file_transfer.log
cp /factory/workers/file_transfer.sh /factory/workers/file_transfer.sh.working
chmod +x /factory/workers/file_transfer_v2.sh
/factory/workers/file_transfer.sh process
tail -f /factory/logs/file_transfer.log
/factory/workers/file_transfer.sh scan | head -20
pkill -f file_transfer.sh
nano /factory/workers/batch_processor.sh
chmod +x /factory/workers/batch_processor.sh
/factory/workers/batch_processor.sh count
/factory/workers/batch_processor.sh run
watch -n 5 "echo 'Output files:'; ls /factory/data/raw/ | wc -l; echo 'Recent log:'; tail -5 /factory/logs/batch_process.log"
pkill -f batch_processor.sh
nano /factory/workers/fast_processor.sh
chmod +x /factory/workers/fast_processor.sh
# Test first with small batch
/factory/workers/fast_processor.sh test
# Run the full processor
/factory/workers/fast_processor.sh run
# In another terminal - monitor live progress
/factory/workers/fast_processor.sh monitor
# Or check progress anytime
/factory/workers/fast_processor.sh progress
watch -n 2 "/factory/workers/fast_processor.sh progress"
tail -f /factory/logs/progress.log
pkill -f fast_processor.sh
pkill -f batch_processor.sh
nano /factory/workers/simple_processor.sh
chmod +x /factory/workers/simple_processor.sh
/factory/workers/simple_processor.sh run
tail -f /factory/logs/tech_collector_v2.log
watch -n 3 "ls -la /factory/data/raw/ | tail -10"
nano /factory/workers/simple_processor.sh
chmod +x /factory/workers/simple_processor.sh
/factory/workers/simple_processor.sh run
watch -n 3 "echo 'Total .txt files:'; ls /factory/data/raw/*.txt 2>/dev/null | wc -l; echo 'Recent files:'; ls -la /factory/data/raw/*.txt 2>/dev/null | tail -5"
watch -n 2 "cat /factory/logs/current_file.log 2>/dev/null"
watch -n 3 "echo 'Total .txt files:'; ls /factory/data/raw/*.txt 2>/dev/null | wc -l; echo 'Recent files:'; ls -la /factory/data/raw/*.txt 2>/dev/null | tail -5"
ps aux | grep simple_processor
df -h /factory/
nano /factory/workers/emergency_processor.sh
chmod +x /factory/workers/emergency_processor.sh
/factory/workers/emergency_processor.sh
/factory/workers/simple_processor.sh run
tail -f /factory/logs/simple_process.log
watch -n 5 "echo 'Files in raw:'; ls -1 /factory/data/raw/*.txt 2>/dev/null | wc -l; echo 'Recent files:'; ls -lt /factory/data/raw/ | head -5"
sudo npm install -g @google/gemini-cli
# Update package manager
sudo apt update
# Install curl if not already installed
sudo apt install -y curl
# Download and run NodeSource setup script for Node.js 20.x
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
# Install Node.js
sudo apt install -y nodejs
# Verify installation
node --version
npm --version
gemini
curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
sudo yum install -y nodejs
# Update package manager
sudo apt update
# Install curl if not already installed
sudo apt install -y curl
# Download and run NodeSource setup script for Node.js 20.x
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
# Install Node.js
sudo apt install -y nodejs
# Verify installation
node --version
npm --version
# Install the Gemini CLI globally
sudo npm install -g @google/gemini-cli
# Remove any corrupted gemini file
sudo rm -f /usr/local/bin/gemini
# Create proper symlink
sudo ln -sf /usr/lib/node_modules/@google/gemini-cli/dist/index.js /usr/local/bin/gemini
# Make executable
sudo chmod +x /usr/local/bin/gemini
gemini --version
gemini
tail -f /factory/logs/language_collector_v2.log
tail -f /factory/logs/archiver.log
sudo ./setup_salvage_extractor.sh
tail -f /factory/logs/salvage_extractor.log
tail -f /factory/logs/jr_librarian_v2.log
tail -f /factory/logs/roda_collector.log
tail -f /factory/logs/data_collector_v2.log
tail -f /factory/logs/business_collector_v2.log
dir
watch -n 2 "/factory/workers/simple_processor.sh status"
gemini
watch -n 2 "/factory/workers/simple_processor.sh status"
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
sudo du -h --max-depth=1
sudo du -h --max-depth=2
sudo du -h --max-depth=5
sudo du -h --max-depth
sudo du -h --max-depth=1
sudo du -h --max-depth1
sudo du -h --max-depth=1
sudo du -h 
dir
cd
cd..
ls blk
tree -L 2 /
tree -L 1 /
cd dev
cd /dev
cd /dev sudo du -h --max-depth=1 /
sudo du -h --max-depth=1 /
df -h
sudo du -h -d1 /factory | sort -h
/dev/mapper/ubuntu--vg-ubuntu--lv  7.3T  4.1T  2.9T  59% /
sudo du -xh / 2>/dev/null | sort -h | tail -n 20
gemini
ls
df -h
cd /dev/mapper/ubuntu--vg-ubuntu--lv
sudo cd /dev/mapper/ubuntu--vg-ubuntu--lv
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
tail -f /factory/logs/ethical_sorter.log
sudo systemctl restart ethical_sorter
tail -f /factory/logs/ethical_sorter.log
htop
btop
sudo apt install btop
btop
gemini
2;45;28M2;45;28m2;46;15M2;46;15m[A
2;33;22M2;33;22m
2;49;10M2;49;10m
sudo du -sh /*
sudo du -sh /factory
cd factory
cd /factory
dir
sudo du 
sudo du -sh /factory/*
sudo du -sh /factory/data/*
ssh-copy-id tdf@192.168.1.123
dir
cd /factory/data/raw
dir
cd data
ls -ld ~/.sshcd 
ls -ld ~/.ssh
ls -l ~/.ssh/authorized_keys
cat ~/.ssh/authorized_keys
cat /etc/ssh/sshd_config | grep -E "SyslogFacility|LogLevel"
sudo journalctl -u sshd --since "1 hour ago"
python -m pip install -U 'anthropic[vertex]'
cd 
pip
python -m pip install -U 'anthropic[vertex]'
sudo apt install python
gemini
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
cd factory
cd /factory
dir
cd data
dir
cd processed_archive
dir
cd archive
cd /archive
cd
cd /archive
cd /factory/data
cd archive
dir
cd raw
ir
dir
cd
df -h
htop
tail -f /factory/logs/ethical_sorter.log
tail -f /factory/logs/ethical_sorter.log
btop
cd /data/raw
cd data/raw
dir
cd factory/data/raw
cd /factory/data/raw
dir
cd data
dir
df -h
dir
cd /factory
dir
cd data
dir
cd archive
cd raw
cd 
echo 'tdf ALL=(ALL) NOPASSWD: ALL' | sudo tee -a /etc/sudoers
gemini
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
cd 
dir
cd factory
cd /factory
cd data
cd archive
cd data
cd raw
dir
rm -rf /from_library
dir
cd from_library
dir
cd pdfs
cd PDFs
dir
cd 
cd /factory/data/archive/raw/from_library
rm -rf PDFs
dir
cd 
gemini
gemini
df -h
cd /factory
cd data
cd archive
cd raw
df -h
cd
/home/tdf/restore_archiver.sh
restore_archiver.sh
sudo restore_archiver.sh
/restore_archiver.sh
sudo mv /home/tdf/migration_worker.py /factory/workers/archivers/main_archiver/migration_worker.py
sudo mv /home/tdf/migration_worker.service /etc/systemd/system/migration_worker.service
sudo systemctl start migration_worker
sudo systemctl enable migration_worker
cd /factory/data/archive/raw
dir
sudo systemctl daemon-reload
sudo systemctl enable new_migration_worker.service
sudo systemctl start new_migration_worker.service
sudo journalctl -u new_migration_worker.service -f
sudo ls -R /factory/data/archive/raw
sudo systemctl status new_migration_worker.service
sudo journalctl -u new_migration_worker.service --since "2025-09-17 14:03:31"
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
/home/tdf/setup_v5/main_monitor_setup/main_monitor.sh
sudo /home/tdf/setup_v5/main_monitor_setup/main_monitor.sh
setup_v5/main_monitor_setup/main_monitor.sh
/home/tdf/setup_v5/main_monitor_setup/main_monitor.sh
/factory/workers/monitors/advanced_monitor/advanced_monitor.sh
cd /factory/workers/.
dir
cd  /factory/processors/
cd 
cd  /factory/processors/
ls -R /factory/workers/processors/
dir
cd /factory/workers/file_transfer.sh.
/home/tdf/setup_main_archiver.sh
/etc/systemd/system/main_archiver.service.
cd /etc/systemd/system/main_archiver.service.
/home/tdf/setup_main_archiver.sh
/setup_main_archiver.sh
gemini
