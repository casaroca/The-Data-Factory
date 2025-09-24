import os
import time
import logging
import requests
import random
from concurrent.futures import ThreadPoolExecutor
import json

# --- Configuration ---
LOG_DIR = "/factory/logs"
RAW_DUMP_DIR = "/factory/data/raw/dpla_harvest"
API_KEY = "f1751ebd62da734ee1d5f580cf7cd402"
MAX_WORKERS = 10
REST_PERIOD_SECONDS = 60 # 1 minute rest period

# High-value queries from your list
SEARCH_QUERIES = [
    "encyclopedia", "dictionary", "almanac", "thesaurus", "atlas", "yearbook", "factbook", "compendium", "gazetteer",
    "philosophy", "logic reasoning", "critical thinking", "epistemology", "metaphysics", "ethics", "moral philosophy",
    "stoicism", "existentialism", "political philosophy", "world history", "ancient history", "medieval history",
    "renaissance history", "modern history", "history of science", "military history", "history of philosophy",
    "cultural history", "biographies historical figures", "classic literature", "world literature", "english literature",
    "american literature", "poetry anthology", "drama plays", "folklore", "mythology", "linguistics",
    "comparative literature", "sociology", "anthropology", "political science", "economics", "psychology",
    "geography human", "demography", "education theory", "law legal texts", "international relations",
    "physics textbooks", "chemistry textbooks", "biology textbooks", "astronomy textbooks", "earth science",
    "mathematics textbooks", "geometry", "algebra", "calculus", "statistics textbooks",
    "computer science", "programming manuals", "artificial intelligence", "machine learning",
    "data structures algorithms", "electronics textbooks", "mechanical engineering", "civil engineering",
    "electrical engineering", "information theory", "medical textbooks", "anatomy textbooks",
    "physiology textbooks", "pathology", "pharmacology", "epidemiology", "public health", "nursing textbooks",
    "psychology clinical", "nutrition science", "art history", "music theory", "architecture history",
    "design principles", "aesthetics philosophy", "theater studies", "film studies", "cultural studies",
    "religion comparative", "mythology comparative", "puzzles riddles", "chess manuals", "go strategy",
    "mathematical logic", "problem solving techniques", "IQ tests", "reasoning tests", "lateral thinking",
    "debate handbooks", "critical essays"
]

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'dpla_harvester.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def get_items_from_api(query):
    """Queries the DPLA API to get a list of items."""
    try:
        logging.info(f"Querying DPLA API for: '{query}'")
        params = {
            'q': query,
            'page_size': 100,
            'api_key': API_KEY
        }
        response = requests.get("https://api.dp.la/v2/items", params=params, headers={'User-Agent': 'DPLAHarvester/1.0'})
        response.raise_for_status()
        data = response.json()
        
        items = data.get('docs', [])
        logging.info(f"API returned {len(items)} results for query '{query}'.")
        return items
    except Exception as e:
        logging.error(f"Could not query DPLA API for '{query}': {e}")
        return []

def process_item(item):
    """Processes a single item from the DPLA, saving its metadata."""
    try:
        item_id = item.get('id')
        if not item_id:
            return
        # DPLA titles can be lists, so we safely access the first one.
        title_list = item.get('sourceResource', {}).get('title', ['No Title'])
        title = title_list[0] if isinstance(title_list, list) else title_list
        logging.info(f"Processing item: {title}")
        
        # The primary data from DPLA is the rich metadata itself
        filename = f"dpla_{item_id}.json"
        output_path = os.path.join(RAW_DUMP_DIR, filename)
        
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(item, f, indent=2, ensure_ascii=False)
            
        logging.info(f"Successfully saved metadata to {output_path}")

    except Exception as e:
        logging.error(f"Failed to process item {item.get('id')}: {e}", exc_info=True)

def main():
    while True:
        logging.info("--- Starting new DPLA Harvester cycle ---")
        
        query = random.choice(SEARCH_QUERIES)
        items = get_items_from_api(query)
        
        if items:
            items_to_process = random.sample(items, min(len(items), 20))
            logging.info(f"Selected {len(items_to_process)} items to process from API query.")
            
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                executor.map(process_item, items_to_process)
        
        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()
