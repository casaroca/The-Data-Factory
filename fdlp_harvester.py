import os
import time
import logging
import subprocess
import sqlite3
import random
from datetime import datetime

# --- Configuration ---
LOG_DIR = "/factory/logs"
DB_PATH = "/factory/db/fdlp_log.db"
BOOK_DEPOSIT_DIR = "/factory/library/book_deposit"
MAX_DOWNLOADS_PER_CYCLE = 40  # Increased from 25
IA_EXECUTABLE = "/factory/workers/collectors/fdlp_harvester_v5/venv/bin/ia"
CYCLE_SLEEP_TIME = 60 # Reduced from 10 minutes

# Expanded list of high-value queries
SEARCH_QUERIES = [
    "collection:usgpo AND mediatype:(texts)",
    "collection:GPO-CONGRESSIONAL-RECORD-BOUND AND mediatype:(texts)",
    "collection:GPO-FEDERAL-REGISTER AND mediatype:(texts)",
    "subject:\"government publication\" AND mediatype:(texts)",
    "collection:us_house_of_representatives AND mediatype:(texts)",
    "collection:uscourts AND mediatype:(texts)",
    "creator:\"Government Printing Office\" AND mediatype:(texts)",
    "publisher:\"U.S. Government Printing Office\" AND mediatype:(texts)"
]

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    filename=os.path.join(LOG_DIR, 'fdlp_harvester.log'),
    level=logging.INFO,
    format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def init_database():
    """Creates a simple database to track processed item identifiers."""
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute('CREATE TABLE IF NOT EXISTS processed_items (identifier TEXT PRIMARY KEY, processed_date TEXT)')
        conn.commit()

def get_item_identifiers_from_api(query):
    """Uses the 'ia' tool to get a list of item identifiers."""
    try:
        logging.info(f"Querying FDLP collections for: '{query}'")
        cmd = [IA_EXECUTABLE, 'search', query, '--itemlist']
        result = subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=300)
        
        if not result.stdout.strip():
            logging.warning("API query returned no results.")
            return []
        
        identifiers = [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
        logging.info(f"API returned {len(identifiers)} results for query.")
        return identifiers
    except subprocess.CalledProcessError as e:
        logging.error(f"Could not query API for '{query}'. Error: {e.stderr}")
        return []
    except Exception as e:
        logging.error(f"An unexpected error occurred during API query for '{query}': {e}")
        return []

def download_item(identifier):
    """Downloads the best available text format for a given item."""
    try:
        with sqlite3.connect(DB_PATH) as conn:
            c = conn.cursor()
            c.execute("SELECT 1 FROM processed_items WHERE identifier=?", (identifier,))
            if c.fetchone():
                logging.info(f"Skipping already processed item: {identifier}")
                return

        logging.info(f"Processing item: {identifier}")
        cmd = [
            IA_EXECUTABLE, 'download', identifier,
            '--glob=*.txt', '--glob=*.pdf',
            '--destdir', BOOK_DEPOSIT_DIR,
            '--no-directories'
        ]
        subprocess.run(cmd, check=True, capture_output=True, timeout=600)
        
        logging.info(f"Successfully downloaded files for item: {identifier}")
        
        with sqlite3.connect(DB_PATH) as conn:
            c = conn.cursor()
            c.execute("INSERT OR IGNORE INTO processed_items VALUES (?, ?)", (identifier, time.strftime('%Y-%m-%d %H:%M:%S')))
            conn.commit()
    except Exception as e:
        logging.error(f"Failed to download item {identifier}: {e.stderr if hasattr(e, 'stderr') else e}")

def main():
    init_database()
    while True:
        logging.info("--- Starting new FDLP Harvester cycle ---")
        
        query = random.choice(SEARCH_QUERIES)
        item_ids = get_item_identifiers_from_api(query)
        
        if item_ids:
            items_to_process = random.sample(item_ids, min(len(item_ids), MAX_DOWNLOADS_PER_CYCLE))
            logging.info(f"Selected {len(items_to_process)} items to download.")
            
            for item_id in items_to_process:
                download_item(item_id)
                time.sleep(2)
        else:
            logging.info("No items found for this query, trying again next cycle.")
        
        logging.info(f"--- Cycle finished. Waiting {CYCLE_SLEEP_TIME/60:.0f} minutes... ---")
        time.sleep(CYCLE_SLEEP_TIME)

if __name__ == "__main__":
    main()
