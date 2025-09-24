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
        headers = {"Authorization": f"Token token=\"{{API_TOKEN}}\""}
        
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
