import os
import requests
import feedparser
import time
import logging
from concurrent.futures import ThreadPoolExecutor

# --- Configuration ---
LOG_DIR = "/factory/logs"
RAW_OUTPUT_DIR = "/factory/data/raw"
MAX_WORKERS = 5 # Increased from 20
REST_PERIOD_SECONDS = 15 # Decreased from 5 minutes

# Expanded list of high-quality business and finance sources
SOURCES=[
    {'url': 'https://feeds.harvard.edu/hbr', 'category': 'business'}, 
    {'url': 'https://www.wsj.com/xml/rss/3_7014.xml', 'category': 'finance'},
    {'url': 'https://www.economist.com/business/rss.xml', 'category': 'business'},
    {'url': 'http://feeds.reuters.com/reuters/businessNews', 'category': 'business'},
    {'url': 'https://www.forbes.com/business/feed/', 'category': 'business'},
    {'url': 'https://www.inc.com/rss/index.xml', 'category': 'business_startups'},
    {'url': 'https://www.entrepreneur.com/latest.rss', 'category': 'business_startups'},
    {'url': 'https://www.wired.com/feed/rss', 'category': 'tech_news'},
    {'url': 'https://arstechnica.com/feed/', 'category': 'tech_news'},
    {'url': 'https://www.technologyreview.com/feed/', 'category': 'tech_news'},
    {'url': 'http://feeds.bbci.co.uk/news/technology/rss.xml', 'category': 'tech_news'},
    {'url': 'https://techcrunch.com/feed/', 'category': 'tech_startups'},
    {'url': 'https://mashable.com/tech/feed/', 'category': 'tech_news'},
    {'url': 'https://www.theverge.com/rss/index.xml', 'category': 'tech_news'},
    {'url': 'https://www.bloomberg.com/opinion/authors/A_2-3c9J9w/matthew-s-levine.rss', 'category': 'finance'},
    {'url': 'https://www.ft.com/rss/home', 'category': 'finance'},
    {'url': 'https://www.marketwatch.com/rss/topstories', 'category': 'finance'},
]

# --- Setup Logging ---
logging.basicConfig(filename=os.path.join(LOG_DIR,'data_collector_v2.log'), level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def dump_raw_content(content, source_category):
    try:
        dir_path = os.path.join(RAW_OUTPUT_DIR, source_category)
        os.makedirs(dir_path, exist_ok=True)
        filename = f"data_collector_v2_{int(time.time()*1000)}.html"
        filepath = os.path.join(dir_path, filename)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        logging.info(f"Dumped file to {filepath}")
    except Exception as e:
        logging.error(f"Failed to dump file for category {source_category}: {e}")

def scrape_rss_source(source):
    try:
        logging.info(f"Scraping RSS: {source['url']}")
        feed = feedparser.parse(source['url'])
        for entry in feed.entries[:5]:
            try:
                response = requests.get(entry.link, headers={'User-Agent': 'DataCollector/2.0'}, timeout=20)
                response.raise_for_status()
                dump_raw_content(response.text, source['category'])
            except Exception as e:
                logging.warning(f"Could not fetch article {entry.link}: {e}")
    except Exception as e:
        logging.error(f"Failed to parse RSS feed {source['url']}: {e}", exc_info=True)

def main():
    while True:
        logging.info("--- Starting new data_collector_v2 cycle ---")
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            for source in SOURCES:
                executor.submit(scrape_rss_source, source)
        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()
