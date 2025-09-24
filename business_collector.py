import os
import requests
import feedparser
import time
import logging
import json
import uuid
import random
from concurrent.futures import ThreadPoolExecutor

# --- Configuration ---
LOG_DIR = "/factory/logs"
RAW_OUTPUT_DIR = "/factory/data/raw/business_collector"
MAX_WORKERS = 10 # Reduced from 15
REST_PERIOD_SECONDS = 60 # Reduced from 5 minutes

SOURCES = {
    'rss': [
        {'url': 'https://feeds.harvard.edu/hbr', 'category': 'business'},
        {'url': 'https://www.wsj.com/xml/rss/3_7014.xml', 'category': 'finance'},
        {'url': 'https://www.forbes.com/business/feed/', 'category': 'business'},
        {'url': 'http://feeds.reuters.com/reuters/businessNews', 'category': 'business'},
        {'url': 'https://www.bloomberg.com/opinion/authors/A_2-3c9J9w/matthew-s-levine.rss', 'category': 'finance'},
        {'url': 'https://www.ft.com/rss/home', 'category': 'finance'},
        {'url': 'https://www.cnbc.com/id/100003114/device/rss/rss.html', 'category': 'business'},
        {'url': 'https://www.investopedia.com/feed.xml', 'category': 'finance'},
    ],
    'sec_filings': {
        'ciks': ['0000320193', '0001652044', '0001018724', '0001318605', '0000789019', '0001045810', '0000078003'], # Apple, Google, Microsoft, Amazon, IBM, Intel, Coca-Cola
        'headers': {'User-Agent': 'Grupo Roca Seguridad info@casarocaseguridad.com'}
    }
}

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    filename=os.path.join(LOG_DIR, 'business_collector.log'),
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logging.getLogger('').addHandler(logging.StreamHandler())

def dump_raw_content(content, source_category, extension):
    try:
        dir_path = os.path.join(RAW_OUTPUT_DIR, source_category)
        os.makedirs(dir_path, exist_ok=True)
        filename = f"{int(time.time() * 1000)}_{str(uuid.uuid4())[:8]}.{extension}"
        filepath = os.path.join(dir_path, filename)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        logging.info(f"Dumped file to {filepath}")
    except Exception as e:
        logging.error(f"Failed to dump file for category {source_category}: {e}", exc_info=True)

def scrape_rss_source(source):
    logging.info(f"Scraping RSS: {source['url']}")
    try:
        feed = feedparser.parse(source['url'])
        for entry in feed.entries[:10]:
            try:
                time.sleep(1) # Be respectful
                response = requests.get(entry.link, headers={'User-Agent': 'BusinessCollector/1.0'}, timeout=20)
                response.raise_for_status()
                dump_raw_content(response.text, source['category'], 'html')
            except Exception as e:
                logging.warning(f"Could not fetch article {entry.link}: {e}")
    except Exception as e:
        logging.error(f"Error scraping RSS {source['url']}: {e}", exc_info=True)

def scrape_sec_filings(sec_config):
    logging.info("Scraping SEC EDGAR filings...")
    try:
        cik = random.choice(sec_config['ciks'])
        api_url = f"https://data.sec.gov/submissions/CIK{cik}.json"
        response = requests.get(api_url, headers=sec_config['headers'], timeout=30)
        response.raise_for_status()
        data = response.json()
        filings_data = data['filings']['recent']
        
        # Prioritize 10-K, then 10-Q, then 8-K
        forms_to_check = ['10-K', '10-Q', '8-K']
        
        for form_type in forms_to_check:
            for i in range(len(filings_data['form'])):
                if filings_data['form'][i] == form_type:
                    acc_no = filings_data['accessionNumber'][i].replace('-', '')
                    doc_name = filings_data['primaryDocument'][i]
                    doc_url = f"https://www.sec.gov/Archives/edgar/data/{cik}/{acc_no}/{doc_name}"
                    logging.info(f"Attempting to download {form_type} from {doc_url}")
                    time.sleep(1) # Be respectful
                    doc_response = requests.get(doc_url, headers=sec_config['headers'], timeout=60)
                    doc_response.raise_for_status()
                    dump_raw_content(doc_response.text, 'sec_filings', 'html')
                    return # Only download one filing per CIK per cycle
        logging.warning(f"No relevant filings (10-K, 10-Q, 8-K) found for CIK {cik}")

    except Exception as e:
        logging.error(f"Error scraping SEC filings for CIK {cik}: {e}", exc_info=True)

def main():
    while True:
        logging.info("--- Starting new Business Collector cycle ---")
        start_time = time.time()
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            for source in SOURCES['rss']:
                executor.submit(scrape_rss_source, source)
            executor.submit(scrape_sec_filings, SOURCES['sec_filings'])
        end_time = time.time()
        logging.info(f"--- Cycle finished in {end_time - start_time:.2f} seconds ---")
        cooldown = REST_PERIOD_SECONDS
        logging.info(f"Waiting {cooldown} seconds before next cycle...")
        time.sleep(cooldown)

if __name__ == "__main__":
    main()