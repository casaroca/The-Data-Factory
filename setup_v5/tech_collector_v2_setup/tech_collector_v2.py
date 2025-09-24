import os
import requests
import feedparser
import time
import logging
import json
import uuid
import random
from concurrent.futures import ThreadPoolExecutor

# --- Configuration ---
LOG_DIR = "/factory/logs"
RAW_OUTPUT_DIR = "/factory/data/raw"
MAX_WORKERS = 25 # Increased worker count
REST_PERIOD_SECONDS = 60 # 1 minute rest period

SOURCES = {
    'rss': [
        {'url': 'https://www.wired.com/feed/rss', 'category': 'tech_news'},
        {'url': 'https://arstechnica.com/feed/', 'category': 'tech_news'},
        {'url': 'https://www.theverge.com/rss/index.xml', 'category': 'tech_news'},
        {'url': 'https://techcrunch.com/feed/', 'category': 'tech_startups'},
        {'url': 'https://hnrss.org/frontpage', 'category': 'tech_hacker_news'},
        {'url': 'https://stackoverflow.blog/feed/', 'category': 'tech_developer_blog'},
        {'url': 'https://github.blog/feed/', 'category': 'tech_developer_blog'},
    ],
    'github_api': {
        'topics': ['generative-ai', 'robotics', 'computer-vision', 'llm', 'machine-learning', 'cybersecurity', 'devops'],
        'token': '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'
    }
}

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    filename=os.path.join(LOG_DIR, 'tech_collector_v2.log'),
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logging.getLogger('').addHandler(logging.StreamHandler())

def dump_raw_content(content, source_category, extension):
    try:
        dir_path = os.path.join(RAW_OUTPUT_DIR, source_category)
        os.makedirs(dir_path, exist_ok=True)
        filename = f"tech_collector_v2_{int(time.time() * 1000)}_{str(uuid.uuid4())[:8]}.{extension}"
        filepath = os.path.join(dir_path, filename)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        logging.info(f"Dumped file to {filepath}")
    except Exception as e:
        logging.error(f"Failed to dump file for category {source_category}: {e}", exc_info=True)

def scrape_rss_source(source):
    try:
        logging.info(f"Scraping RSS: {source['url']}")
        feed = feedparser.parse(source['url'])
        for entry in feed.entries[:5]:
            try:
                response = requests.get(entry.link, headers={'User-Agent': 'TechCollector/2.0'}, timeout=20)
                response.raise_for_status()
                dump_raw_content(response.text, source['category'], 'html')
            except Exception as e:
                logging.warning(f"Could not fetch article {entry.link}: {e}")
    except Exception as e:
        logging.error(f"Could not parse RSS feed {source['url']}: {e}", exc_info=True)

def scrape_github(config):
    headers = {'Authorization': f"token {config['token']}"}
    topic = random.choice(config['topics'])
    try:
        logging.info(f"Querying GitHub API for topic: {topic}")
        url = f"https://api.github.com/search/repositories?q={topic}&sort=stars&order=desc&per_page=5"
        response = requests.get(url, headers=headers, timeout=20)
        response.raise_for_status()
        dump_raw_content(response.text, f"github_{topic}_repos", 'json')
    except Exception as e:
        logging.error(f"Failed to query GitHub for topic {topic}: {e}", exc_info=True)

def main():
    while True:
        logging.info("--- Starting new Tech Collector v2 cycle ---")
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            for source in SOURCES['rss']:
                executor.submit(scrape_rss_source, source)
            # Run multiple GitHub queries per cycle
            for _ in range(3):
                executor.submit(scrape_github, SOURCES['github_api'])
        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()
