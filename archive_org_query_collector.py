import os
import time
import logging
import requests
from bs4 import BeautifulSoup
import random
import re
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urljoin

# --- Configuration ---
LOG_DIR = "/factory/logs"
BOOK_DEPOSIT_DIR = "/library/book_deposit"
MAX_WORKERS = 5
REST_PERIOD_SECONDS = 10

# High-value keywords for targeted API queries
SEARCH_QUERIES = [
    "interpersonal skills", "etiquette", "generative ai", "language models",
    "vision models", "healthcare data", "finance fraud detection", "autonomous vehicles",
    "natural language processing", "sentiment analysis", "reinforcement learning",
    "time series data", "tabular data classification", "history", "science", "literature",
    "philosophy", "mathematics", "computer science", "economics", "biology", "physics",
    "chemistry", "engineering", "medicine", "law", "art", "music", "poetry"
]
BASE_URL = "https://archive.org"
API_URL = "https://archive.org/advancedsearch.php"

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'archive_org_query_collector.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def get_item_identifiers_from_api(query):
    """Queries the Internet Archive API to get a list of item identifiers."""
    try:
        logging.info(f"Querying Archive.org API for: '{query}'")
        params = {
            'q': f'({query}) AND mediatype:(texts) AND publicdate:[2000-01-01 TO 2025-01-01]',
            'fl[]': 'identifier',
            'rows': '150', # Get a larger list of results
            'output': 'json'
        }
        response = requests.get(API_URL, params=params, headers={'User-Agent': 'ArchiveQueryCollector/1.0'})
        response.raise_for_status()
        data = response.json()
        
        docs = data.get('response', {}).get('docs', [])
        identifiers = [doc['identifier'] for doc in docs]
        logging.info(f"API returned {len(identifiers)} results for query '{query}'.")
        return identifiers
    except Exception as e:
        logging.error(f"Could not query API for '{query}': {e}")
        return []

def download_book(identifier):
    """Visits an item page by its identifier and downloads the best available format."""
    item_url = f"{BASE_URL}/details/{identifier}"
    try:
        logging.info(f"Processing item page: {item_url}")
        response = requests.get(item_url, headers={'User-Agent': 'ArchiveQueryCollector/1.0'}, timeout=60)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'lxml')

        # Prioritize TXT and PDF files
        download_options = [
            ('txt', soup.find('a', string=re.compile(r'FULL TEXT', re.IGNORECASE))),
            ('pdf', soup.find('a', string=re.compile(r'PDF', re.IGNORECASE)))
        ]

        download_url, file_type = None, None
        for ftype, link in download_options:
            if link and link.has_attr('href'):
                download_url = urljoin(item_url, link['href'])
                file_type = ftype
                break

        if not download_url:
            logging.warning(f"No TXT or PDF download link found on {item_url}")
            return

        logging.info(f"Found {file_type.upper()} link: {download_url}")
        time.sleep(1)
        
        book_content_response = requests.get(download_url, headers={'User-Agent': 'ArchiveQueryCollector/1.0'}, timeout=600)
        book_content_response.raise_for_status()

        title = soup.find('h1').text.strip() if soup.find('h1') else identifier
        filename = re.sub(r'[<>:"/\\|?*]', '_', title) + f".{file_type}"
        output_path = os.path.join(BOOK_DEPOSIT_DIR, filename)
        
        with open(output_path, 'wb') as f:
            f.write(book_content_response.content)
        
        logging.info(f"Successfully downloaded: {filename}")

    except Exception as e:
        logging.error(f"Failed to download book from {item_url}: {e}", exc_info=True)

def main():
    while True:
        logging.info("--- Starting new Archive.org Query Collector cycle ---")
        
        query = random.choice(SEARCH_QUERIES)
        item_ids = get_item_identifiers_from_api(query)
        
        if item_ids:
            items_to_process = random.sample(item_ids, min(len(item_ids), 15))
            logging.info(f"Selected {len(items_to_process)} items to process from API query.")
            
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                executor.map(download_book, items_to_process)
        
        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()
