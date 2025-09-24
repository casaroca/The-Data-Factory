import os
import time
import logging
import sqlite3
from concurrent.futures import ThreadPoolExecutor
import ebooklib
from ebooklib import epub
from bs4 import BeautifulSoup

# --- Configuration ---
LOG_DIR = "/factory/logs"
DB_PATH = "/factory/db/topic_puller.db"
LIBRARY_DIR = "/factory/library/library"
RAW_DUMP_DIR = "/factory/data/inbox"
MAX_WORKERS = 10
DB_TIMEOUT = 30.0
CYCLE_TIME_SECONDS = 60

TOPICS = {
    "technology": ["software", "python", "computer", "network", "cybersecurity", "programming", "algorithm"],
    "business": ["management", "marketing", "finance", "investment", "strategy", "economics", "startup"],
    "science": ["physics", "biology", "chemistry", "astronomy", "research", "genetics", "mathematics"],
    "history": ["history", "ancient", "war", "revolution", "historical", "civilization"],
    "language": ["language", "linguistics", "grammar", "spanish", "english", "translate"]
}

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'topic_puller.log'), level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def init_database():
    """Ensures a dedicated table exists to track processed file paths."""
    try:
        with sqlite3.connect(DB_PATH, timeout=DB_TIMEOUT) as conn:
            cursor = conn.cursor()
            cursor.execute('''CREATE TABLE IF NOT EXISTS processed_files (
                                filepath TEXT PRIMARY KEY,
                                processed_date TEXT
                             )''')
            conn.commit()
    except sqlite3.OperationalError as e:
        logging.error(f"Database is locked, could not initialize: {e}")

def get_unprocessed_epubs():
    """
    Scans the entire library directory for EPUBs and checks them against the dedicated log database.
    """
    all_epubs = []
    logging.info("Scanning entire library for EPUB files...")
    for dirpath, _, filenames in os.walk(LIBRARY_DIR):
        for filename in filenames:
            if filename.lower().endswith('.epub'):
                all_epubs.append(os.path.join(dirpath, filename))
    
    if not all_epubs:
        return []

    try:
        with sqlite3.connect(DB_PATH, timeout=DB_TIMEOUT) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT filepath FROM processed_files")
            processed_files = {row[0] for row in cursor.fetchall()}
        
        unprocessed = [fp for fp in all_epubs if fp not in processed_files]
        logging.info(f"Scan complete. Found {len(all_epubs)} total EPUBs, {len(unprocessed)} are new.")
        return unprocessed
    except sqlite3.OperationalError as e:
        logging.warning(f"Database is locked, cannot get new books this cycle: {e}")
        return []

def mark_file_as_processed(filepath):
    """Marks a file as processed in the dedicated log database."""
    try:
        with sqlite3.connect(DB_PATH, timeout=DB_TIMEOUT) as conn:
            cursor = conn.cursor()
            cursor.execute("INSERT OR IGNORE INTO processed_files VALUES (?, ?)", (filepath, time.strftime('%Y-%m-%d %H:%M:%S')))
            conn.commit()
    except sqlite3.OperationalError as e:
        logging.error(f"Database is locked, could not mark file {os.path.basename(filepath)} as processed: {e}")

def extract_text_from_epub(epub_path):
    """Extracts all text content from an EPUB file."""
    try:
        book = epub.read_epub(epub_path)
        content = ""
        for item in book.get_items_of_type(ebooklib.ITEM_DOCUMENT):
            soup = BeautifulSoup(item.get_body_content(), 'html.parser', from_encoding='utf-8')
            [s.decompose() for s in soup(['script', 'style'])]
            content += soup.get_text('\n', strip=True) + "\n\n"
        return content
    except Exception as e:
        logging.error(f"Could not read EPUB {os.path.basename(epub_path)}: {e}")
        return ""

def pull_topics_from_book(filepath):
    """Processes a single book, extracts relevant topics, and saves them as text files."""
    if not os.path.exists(filepath):
        logging.warning(f"File not found, skipping: {filepath}")
        mark_file_as_processed(filepath)
        return
    
    logging.info(f"Processing book: {os.path.basename(filepath)}")
    full_text = extract_text_from_epub(filepath)
    if not full_text:
        mark_file_as_processed(filepath)
        return

    paragraphs = [p.strip() for p in full_text.split('\n') if len(p.strip()) > 100]
    
    for topic, keywords in TOPICS.items():
        relevant_paragraphs = [p for p in paragraphs if any(kw in p.lower() for kw in keywords)]
        if relevant_paragraphs:
            output_content = "\n\n".join(relevant_paragraphs)
            base_filename = os.path.splitext(os.path.basename(filepath))[0]
            output_filename = f"topic_{topic}_{base_filename}.txt"
            output_filepath = os.path.join(RAW_DUMP_DIR, output_filename)
            
            with open(output_filepath, 'w', encoding='utf-8') as f:
                f.write(output_content)
            logging.info(f"Dumped {len(relevant_paragraphs)} paragraphs on '{topic}' to inbox")
    
    mark_file_as_processed(filepath)

def main():
    init_database()
    while True:
        logging.info("--- Topic Puller starting new cycle ---")
        books_to_process = get_unprocessed_epubs()
        
        if books_to_process:
            logging.info(f"Found {len(books_to_process)} new books to extract topics from.")
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                # Process a batch of up to 100 books per cycle
                executor.map(pull_topics_from_book, books_to_process[:100])
            logging.info(f"Finished processing batch.")
        else:
            logging.info("No new EPUBs to process in the main library.")
        
        logging.info(f"--- Cycle finished. Waiting {CYCLE_TIME_SECONDS} seconds... ---")
        time.sleep(CYCLE_TIME_SECONDS)

if __name__ == "__main__":
    main()