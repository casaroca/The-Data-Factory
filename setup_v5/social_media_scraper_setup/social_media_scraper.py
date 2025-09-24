import os
import time
import logging
import re
import json
from selenium import webdriver
from selenium.webdriver.chrome.service import Service as ChromeService
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.options import Options
from selenium.common.exceptions import TimeoutException
from concurrent.futures import ThreadPoolExecutor

# --- Configuration ---
LOG_DIR = "/factory/logs"
RAW_OUTPUT_DIR = "/factory/data/raw/social_media_reddit"
MAX_WORKERS = 3
REST_PERIOD_SECONDS = 30 # 30 seconds

# List of subreddits to scrape
SUBREDDITS = ["history", "science", "technology", "futurology", "philosophy", "explainlikeimfive", "AskHistorians"]

# --- Setup Logging ---
logging.basicConfig(filename=os.path.join(LOG_DIR,'social_media_scraper.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def get_driver():
    """Initializes a Selenium WebDriver instance."""
    options = Options()
    options.add_argument("--headless")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
    options.add_argument("user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")
    # Selenium will automatically find the system-installed chromedriver
    return webdriver.Chrome(options=options)

def scrape_subreddit(subreddit):
    """Scrapes the top posts from a given subreddit for the day."""
    driver = None
    try:
        driver = get_driver()
        url = f"https://www.reddit.com/r/{subreddit}/top/?t=day"
        logging.info(f"Scraping subreddit: {url}")
        driver.get(url)
        time.sleep(5) # Allow page to load

        # Scroll down to load more posts
        driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")
        time.sleep(3)

        posts = driver.find_elements(By.CSS_SELECTOR, 'a[data-testid="post-title"]')
        post_links = [post.get_attribute('href') for post in posts[:10]] # Get top 10 post links

        for link in post_links:
            try:
                driver.get(link)
                time.sleep(4)
                
                title = driver.find_element(By.CSS_SELECTOR, 'h1').text
                
                # Find all comment elements and extract their text
                comments = driver.find_elements(By.CSS_SELECTOR, 'div[data-testid="comment"]')
                comment_texts = [comment.text for comment in comments]
                
                full_text = f"Title: {title}\n\n" + "\n\n---\n\n".join(comment_texts)
                
                # Save content
                filename = f"reddit_{subreddit}_{int(time.time() * 1000)}.txt"
                filepath = os.path.join(RAW_OUTPUT_DIR, filename)
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(full_text)
                logging.info(f"Saved discussion from {link}")

            except Exception as e:
                logging.warning(f"Could not scrape post {link}: {e}")
                continue # Move to the next post

    except Exception as e:
        logging.error(f"Failed to scrape subreddit {subreddit}: {e}", exc_info=True)
    finally:
        if driver:
            driver.quit()

def main():
    while True:
        logging.info("--- Starting new Social Media Scraper cycle ---")
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            executor.map(scrape_subreddit, SUBREDDITS)
        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()
