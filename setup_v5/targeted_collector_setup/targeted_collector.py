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
MAX_WORKERS = 10
REST_PERIOD_SECONDS = 30 # Updated rest time

# --- List of Target URLs to Scrape ---
# This list can be manually updated as needed.
TARGET_URLS = [
    "https://archive.org/details/cdl",
    "https://archive.org/details/umass_amherst_libraries",
    "https://archive.org/details/tischlibrary",
    "https://archive.org/details/delawarecountydistrictlibrary",
    "https://archive.org/details/computerworld",
    "https://archive.org/details/northeastern",
    "https://archive.org/details/dulua",
    "https://archive.org/details/mugar",
    "https://archive.org/details/aipi.ua-collection",
    "https://archive.org/details/texts?tab=collection&query=artificial+intelligence+llm",
    "https://archive.org/details/texts?tab=collection&query=llm"
]

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'targeted_collector.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def get_ebook_links_from_page(page_url):
    """Scrapes a single page to find all ebook links."""
    try:
        logging.info(f"Fetching ebook links from: {page_url}")
        response = requests.get(page_url, headers={'User-Agent': 'TargetedCollector/1.0'})
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'lxml')
        links = set()
        
        # This selector is specific to archive.org's layout
        links.update(urljoin(page_url, a['href']) for a in soup.select('div.item-tile > a'))

        return list(links)
    except Exception as e:
        logging.error(f"Could not fetch links from {page_url}: {e}")
        return []

def download_book(ebook_page_url):
    """Visits an ebook page, finds the plain text link, and downloads the book."""
    try:
        logging.info(f"Processing book page: {ebook_page_url}")
        response = requests.get(ebook_page_url, headers={'User-Agent': 'TargetedCollector/1.0'})
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'lxml')

        download_url = None
        # Find the most likely plain text download link
        text_link = soup.find('a', string=re.compile(r'FULL TEXT', re.IGNORECASE))
        if text_link:
            download_url = urljoin(ebook_page_url, text_link['href'])

        if not download_url:
            logging.warning(f"No plain text link found for {ebook_page_url}")
            return

        time.sleep(1) # Be respectful
        book_content_response = requests.get(download_url, headers={'User-Agent': 'TargetedCollector/1.0'})
        book_content_response.raise_for_status()

        title = soup.find('h1').text.strip() if soup.find('h1') else f"ebook_{int(time.time())}"
        filename = re.sub(r'[<>:"/\\|?*]', '_', title) + ".txt"
        output_path = os.path.join(BOOK_DEPOSIT_DIR, filename)
        
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(book_content_response.text)
        
        logging.info(f"Successfully downloaded: {filename}")

    except Exception as e:
        logging.error(f"Failed to download book from {ebook_page_url}: {e}", exc_info=True)

def main():
    while True:
        logging.info("--- Starting new Targeted Collector cycle ---")
        
        all_links_to_process = []
        for url in TARGET_URLS:
            all_links_to_process.extend(get_ebook_links_from_page(url))
        
        if all_links_to_process:
            logging.info(f"Found a total of {len(all_links_to_process)} ebooks to download.")
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                executor.map(download_book, all_links_to_process)
        
        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()
