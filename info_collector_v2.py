import os
import requests
import feedparser
import time
import logging
import uuid
from concurrent.futures import ThreadPoolExecutor

# --- Configuration ---
LOG_DIR = "/factory/logs"
RAW_OUTPUT_DIR = "/factory/data/raw"
MAX_WORKERS = 10 # Increased for the large number of sources
REST_PERIOD_SECONDS = 15 # 1 minute rest period

# Massively expanded list of international sources
SOURCES=[
    # World News
    {'url': 'http://feeds.reuters.com/Reuters/worldNews', 'category': 'world_news'},
    {'url': 'http://feeds.bbci.co.uk/news/world/rss.xml', 'category': 'world_news'},
    {'url': 'https://www.aljazeera.com/xml/rss/all.xml', 'category': 'world_news'},
    {'url': 'https://rss.nytimes.com/services/xml/rss/nyt/World.xml', 'category': 'world_news'},
    {'url': 'https://www.theguardian.com/world/rss', 'category': 'world_news'},
    {'url': 'https://www.cbsnews.com/latest/rss/world', 'category': 'world_news'},
    {'url': 'https://feeds.npr.org/1004/rss.xml', 'category': 'world_news'},
    
    # Science & Technology
    {'url': 'https://www.sciencedaily.com/rss/top/science.xml', 'category': 'science_news'},
    {'url': 'https://phys.org/rss-feed/', 'category': 'science_news'},
    {'url': 'https://www.technologyreview.com/feed/', 'category': 'tech_review'},
    {'url': 'https://arstechnica.com/feed/', 'category': 'tech_news'},
    {'url': 'https://www.wired.com/feed/rss', 'category': 'tech_news'},
    {'url': 'https://techcrunch.com/feed/', 'category': 'tech_startups'},
    {'url': 'https://mashable.com/tech/feed/', 'category': 'tech_news'},
    {'url': 'https://www.theverge.com/rss/index.xml', 'category': 'tech_news'},

    # General Knowledge & Culture
    {'url': 'https://www.smithsonianmag.com/rss/latest/', 'category': 'general_knowledge'},
    {'url': 'https://www.nationalgeographic.com/rss/news', 'category': 'general_knowledge'},
    {'url': 'https://longform.org/feed', 'category': 'longform_articles'},
    {'url': 'https://www.history.com/.rss/full/history-news', 'category': 'history_news'},
    {'url': 'https://www.artsy.net/rss', 'category': 'art_culture'},
    {'url': 'https://www.brainpickings.org/feed/', 'category': 'philosophy_culture'},
    {'url': 'https://aeon.co/feed.rss', 'category': 'philosophy_culture'},
    {'url': 'https://www.newyorker.com/feed/culture', 'category': 'culture'},
    {'url': 'https://www.atlasobscura.com/feeds/latest', 'category': 'curiosity'},
]

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'info_collector_v2.log'), level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def dump_raw_content(content, source_category):
    try:
        dir_path = os.path.join(RAW_OUTPUT_DIR, source_category)
        os.makedirs(dir_path, exist_ok=True)
        filename = f"info_collector_v2_{int(time.time()*1000)}.html"
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
        for entry in feed.entries[:5]: # Get top 5 entries from each feed
            try:
                response = requests.get(entry.link, headers={'User-Agent': 'InfoCollector/2.0'}, timeout=20)
                response.raise_for_status()
                dump_raw_content(response.text, source['category'])
            except Exception as e:
                logging.warning(f"Could not fetch article {entry.link}: {e}")
    except Exception as e:
        logging.error(f"Failed to parse RSS feed {source['url']}: {e}", exc_info=True)

def main():
    while True:
        logging.info("--- Starting new Info Collector v2 cycle ---")
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            for source in SOURCES:
                executor.submit(scrape_rss_source, source)
        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()
