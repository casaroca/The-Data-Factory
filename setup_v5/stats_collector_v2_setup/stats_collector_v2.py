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
        logging.error(f"Failed to dump file for category {source_category}: {e}")

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
