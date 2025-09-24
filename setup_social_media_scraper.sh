#!/bin/bash
set -e

echo "--- Setting up Social Media Scraper (Reddit) ---"

# --- 1. System Prerequisites ---
echo "[+] Installing prerequisites (Chrome, Chromedriver, Python)..."
export NEEDRESTART_MODE=a
sudo apt-get update
# Removed chromium-browser, rely on google-chrome-stable and the separate chromedriver package
sudo apt-get install -y python3-pip python3-venv wget gnupg chromium-chromedriver

# Install Google Chrome (if not already present)
if ! command -v google-chrome &> /dev/null
then
    wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
    sudo sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list'
    sudo apt-get update
    sudo apt-get install -y google-chrome-stable
fi

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/social_media_scraper"
LOG_DIR="/factory/logs"
DUMP_DIR="/factory/data/raw/social_media_reddit"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project directories..."
mkdir -p $PROJECT_DIR
mkdir -p $DUMP_DIR

# --- 4. Create Application Files ---
echo "[+] Creating application files..."
cat << 'EOF' > $PROJECT_DIR/social_media_scraper.py
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
                
                full_text = f"Title: {title}\n\n" + "\n\n--- Comment ---\n\n".join(comment_texts)
                
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
EOF

cat << 'EOF' > $PROJECT_DIR/requirements.txt
selenium
EOF

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/social_media_scraper.service
[Unit]
Description=Social Media Scraper Service (Reddit)
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 social_media_scraper.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting Social Media Scraper service..."
sudo chown -R $USER:$USER /factory
sudo systemctl daemon-reload
sudo systemctl start social_media_scraper
sudo systemctl enable social_media_scraper

echo "--- Social Media Scraper Setup Complete ---"
echo "To check the status, run: sudo systemctl status social_media_scraper"
echo "To watch the logs, run: tail -f /factory/logs/social_media_scraper.log"
