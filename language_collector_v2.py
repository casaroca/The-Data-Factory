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
MAX_WORKERS = 10 # Increased worker count
REST_PERIOD_SECONDS = 15 # 1 minute rest period

# Expanded list of international language sources
SOURCES=[
    # Spanish
    {'url': 'https://www.vozdeamerica.com/rss/', 'category': 'news_es'},
    {'url': 'https://www.univision.com/feeds/noticias', 'category': 'news_es'},
    {'url': 'https://feeds.bbci.co.uk/mundo/rss.xml', 'category': 'news_es'},
    {'url': 'https://es.globalvoices.org/feed/', 'category': 'bilingual_news_es'},
    {'url': 'https://elpais.com/rss/elpais/portada.xml', 'category': 'news_es'},
    {'url': 'https://www.rtve.es/rss/temas/noticias.xml', 'category': 'news_es'},
    {'url': 'https://www.infobae.com/feeds/rss/', 'category': 'news_es'},
    # English
    {'url': 'https://rss.nytimes.com/services/xml/rss/nyt/World.xml', 'category': 'news_en'},
    {'url': 'https://www.theguardian.com/world/rss', 'category': 'news_en'},
    {'url': 'http://feeds.reuters.com/Reuters/worldNews', 'category': 'news_en'},
    {'url': 'http://feeds.bbci.co.uk/news/world/rss.xml', 'category': 'news_en'},
    {'url': 'https://www.aljazeera.com/xml/rss/all.xml', 'category': 'news_en'},
    # French
    {'url': 'https://www.lemonde.fr/rss/en_continu.xml', 'category': 'news_fr'},
    {'url': 'https://www.rfi.fr/fr/rss', 'category': 'news_fr'},
    {'url': 'https://www.france24.com/fr/rss', 'category': 'news_fr'},
    # German
    {'url': 'https://www.spiegel.de/international/index.rss', 'category': 'news_de'},
    {'url': 'https://www.dw.com/de/themen/s-11790/rss', 'category': 'news_de'},
    {'url': 'https://www.zeit.de/index?page=rss', 'category': 'news_de'},
]

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'language_collector_v2.log'), level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def dump_raw_content(content, source_category):
    try:
        dir_path = os.path.join(RAW_OUTPUT_DIR, source_category)
        os.makedirs(dir_path, exist_ok=True)
        filename = f"language_collector_v2_{int(time.time()*1000)}.html"
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
                response = requests.get(entry.link, headers={'User-Agent': 'LanguageCollector/2.0'}, timeout=20)
                response.raise_for_status()
                dump_raw_content(response.text, source['category'])
            except Exception as e:
                logging.warning(f"Could not fetch article {entry.link}: {e}")
    except Exception as e:
        logging.error(f"Failed to parse RSS feed {source['url']}: {e}", exc_info=True)

def main():
    while True:
        logging.info("--- Starting new language_collector_v2 cycle ---")
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            for source in SOURCES:
                executor.submit(scrape_rss_source, source)
        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()
