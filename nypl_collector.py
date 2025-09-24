import os
import json
import requests
import time
import logging
import random
from concurrent.futures import ThreadPoolExecutor

# --- Configuration ---
LOG_DIR = "/factory/logs"
RAW_OUTPUT_DIR = "/factory/data/raw/nypl_api"
API_TOKEN = "3l5l2c89hm4qcbqt"

BASE_URL = "http://api.repo.nypl.org/api/v2/"
SEARCH_ENDPOINT = "items/search"

SEARCH_TERMS = ["history", "science", "new york", "maps", "manuscripts", "photography", "art", "literature", "letters", "diaries"]
REST_PERIOD_SECONDS = 15 # Reduced from 60
MAX_WORKERS = 5 # Kept at 5

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

def fetch_nypl_data(search_term, pages=3): # Reduced pages to 3 for faster testing
    """
    Fetches data from the NYPL API for a given search term over several pages.

    Args:
        search_term (str): The term to search for.
        pages (int): The number of pages of results to retrieve.

    Returns:
        list: A list of all captured items, or None if an error occurs.
    """
    if not API_TOKEN or API_TOKEN == "YOUR_NEW_NYPL_API_TOKEN":
        logging.error("🛑 Error: API token is not set. Please set the NYPL_API_TOKEN environment variable or hardcode it.")
        return None

    all_captures = []
    logging.info(f"🚀 Starting search for '{search_term}'...")

    headers = {
        "Authorization": f"Token token={API_TOKEN}"
    }

    for page_num in range(1, pages + 1):
        params = {
            "q": search_term,
            "publicDomainOnly": "true",
            "page": page_num
        }
        
        try:
            logging.info(f"    - Fetching page {page_num} of {pages}...")
            response = requests.get(f"{BASE_URL}{SEARCH_ENDPOINT}", headers=headers, params=params, timeout=15)
            
            # This will raise an exception for bad status codes (4xx or 5xx)
            response.raise_for_status() 

            data = response.json()
            # The actual results are nested inside the response
            captures = data.get('nyplAPI', {}).get('response', {}).get('capture', [])
            
            if not captures:
                logging.info("    - No more results found. Stopping.")
                break
            
            all_captures.extend(captures)

        except requests.exceptions.RequestException as e:
            logging.error(f"❌ An error occurred: {e}")
            return None
            
    return all_captures

def main():
    while True:
        logging.info("--- Starting new NYPL Collector cycle ---")
        
        # Query 3 random terms per cycle to vary the data
        selected_terms = random.sample(SEARCH_TERMS, min(len(SEARCH_TERMS), 3))
        
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            futures = {executor.submit(fetch_nypl_data, term, pages=3): term for term in selected_terms}
            for future in futures:
                results = future.result()
                if results:
                    dump_raw_content(results, futures[future])
        
        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()
