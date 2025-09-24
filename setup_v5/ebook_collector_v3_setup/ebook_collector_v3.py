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
DEPOSIT_DIR = "/factory/library/book_deposit"
MAX_WORKERS = 15
REST_PERIOD_SECONDS = 60

# Expanded list of public domain ebook sources
SOURCES = {
    "gutenberg": {"list_url": "https://www.gutenberg.org/browse/scores/top"},
    "standard_ebooks": {"list_url": "https://standardebooks.org/ebooks"},
    "internet_archive": {"list_url": "https://archive.org/details/texts?sort=-publicdate"},
    "hathitrust": {"list_url": "https://babel.hathitrust.org/cgi/mb?a=listis;c=1495534215"},
    "feedbooks": {"list_url": "http://www.feedbooks.com/publicdomain"}
}

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'ebook_collector_v3.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def get_ebook_links(source_name, config):
    try:
        logging.info(f"Fetching ebook list from: {source_name}")
        response = requests.get(config['list_url'], headers={'User-Agent': 'EbookCollector/3.0'})
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'lxml')
        links = set()
        
        if source_name == "gutenberg":
            links.update(urljoin(config['list_url'], a['href']) for a in soup.find_all('a') if a.get('href', '').startswith('/ebooks/'))
        elif source_name == "standard_ebooks":
            links.update(a['href'] for a in soup.select('li.ebook-entry > a'))
        elif source_name == "internet_archive":
            links.update(urljoin(config['list_url'], a['href']) for a in soup.select('div.item-tile > a'))
        elif source_name == "hathitrust":
            links.update(a['href'] for a in soup.select('a[href*="handle.net"]'))
        elif source_name == "feedbooks":
            links.update(urljoin(config['list_url'], a['href']) for a in soup.select('a.book-title'))

        return list(links)
    except Exception as e:
        logging.error(f"Could not fetch ebook list from {source_name}: {e}")
        return []

def download_book(ebook_page_url):
    try:
        logging.info(f"Processing book page: {ebook_page_url}")
        response = requests.get(ebook_page_url, headers={'User-Agent': 'EbookCollector/3.0'})
        response.raise_for_status()
        soup = BeautifulSoup(response.text, 'lxml')

        download_url, file_type = None, None
        
        # Prioritize EPUB then PDF
        epub_link = soup.find('a', href=re.compile(r'\.epub', re.IGNORECASE))
        pdf_link = soup.find('a', href=re.compile(r'\.pdf', re.IGNORECASE))

        if epub_link:
            download_url, file_type = urljoin(ebook_page_url, epub_link['href']), 'epub'
        elif pdf_link:
            download_url, file_type = urljoin(ebook_page_url, pdf_link['href']), 'pdf'

        if not download_url:
            logging.warning(f"No EPUB or PDF link found for {ebook_page_url}")
            return

        time.sleep(1)
        book_content_response = requests.get(download_url, headers={'User-Agent': 'EbookCollector/3.0'})
        book_content_response.raise_for_status()

        title = soup.find('h1').text.strip() if soup.find('h1') else f"ebook_{int(time.time())}"
        filename = re.sub(r'[<>:"/\\|?*]', '_', title) + f".{file_type}"
        output_path = os.path.join(DEPOSIT_DIR, filename)
        
        with open(output_path, 'wb') as f:
            f.write(book_content_response.content)
        
        logging.info(f"Successfully downloaded: {filename}")

    except Exception as e:
        logging.error(f"Failed to download book from {ebook_page_url}: {e}", exc_info=True)

def main():
    while True:
        logging.info("--- Starting new Ebook Collector v3 cycle ---")
        
        all_links = []
        for name, config in SOURCES.items():
            all_links.extend(get_ebook_links(name, config))
        
        if all_links:
            books_to_download = random.sample(all_links, min(len(all_links), 15))
            logging.info(f"Selected {len(books_to_download)} books for this cycle.")
            
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                executor.map(download_book, books_to_download)
        
        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()
