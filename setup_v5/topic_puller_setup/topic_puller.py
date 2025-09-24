import os
import time
import logging
import re
import sqlite3
from concurrent.futures import ThreadPoolExecutor
import subprocess
import shutil

# --- Configuration ---
LOG_DIR = "/factory/logs"
DB_PATH = "/factory/db/library.db"
LIBRARY_DIR = "/factory/library/library"
DISCARD_BIN = "/factory/library/discarded"
SALVAGED_OUTPUT_DIR = "/factory/data/raw/salvaged_from_discard"
UNSALVAGEABLE_DIR = "/factory/library/discarded/unsalvageable_pdfs"
MAX_WORKERS = 10
DB_TIMEOUT = 30.0

TOPICS = {
    "technology": ["software", "python", "computer", "network", "cybersecurity", "programming"],
    "business": ["management", "marketing", "finance", "investment", "strategy", "economics"],
    "science": ["physics", "biology", "chemistry", "astronomy", "research", "genetics"],
    "history": ["history", "ancient", "war", "revolution", "historical"],
    "language": ["language", "linguistics", "grammar", "spanish", "english"]
}

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'topic_puller.log'), level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def init_database():
    try:
        with sqlite3.connect(DB_PATH, timeout=DB_TIMEOUT) as conn:
            cursor = conn.cursor()
            try:
                cursor.execute("ALTER TABLE books ADD COLUMN processed_by_topic_puller BOOLEAN DEFAULT 0")
            except sqlite3.OperationalError:
                pass # Column already exists
            conn.commit()
    except sqlite3.OperationalError as e:
        logging.error(f"Database is locked, could not initialize: {e}")

def get_unprocessed_books():
    try:
        with sqlite3.connect(DB_PATH, timeout=DB_TIMEOUT) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT id, filepath FROM books WHERE processed_by_topic_puller = 0 AND filepath LIKE '%.epub' LIMIT 100")
            return cursor.fetchall()
    except sqlite3.OperationalError as e:
        logging.warning(f"Database is locked, cannot get new books this cycle: {e}")
        return []

def mark_book_as_processed(book_id):
    try:
        with sqlite3.connect(DB_PATH, timeout=DB_TIMEOUT) as conn:
            cursor = conn.cursor()
            cursor.execute("UPDATE books SET processed_by_topic_puller = 1 WHERE id = ?", (book_id,))
            conn.commit()
    except sqlite3.OperationalError as e:
        logging.error(f"Database is locked, could not mark book {book_id} as processed: {e}")

def pull_topics_from_book(book_info):
    # This function is a placeholder for the EPUB topic extraction logic
    book_id, filepath = book_info
    mark_book_as_processed(book_id)

def salvage_pdf(pdf_path):
    """Extracts text from a PDF using pdftotext."""
    filename = os.path.basename(pdf_path)
    logging.info(f"Attempting to salvage text from PDF: {filename}")
    try:
        result = subprocess.run(['pdftotext', pdf_path, '-'], capture_output=True, text=True, errors='ignore', timeout=300)
        
        if result.returncode == 0 and result.stdout.strip():
            salvaged_text = result.stdout
            output_filename = os.path.splitext(filename)[0] + ".txt"
            output_path = os.path.join(SALVAGED_OUTPUT_DIR, output_filename)
            
            with open(output_path, 'w', encoding='utf-8') as f:
                f.write(salvaged_text)
            logging.info(f"Successfully salvaged text to {output_path}")
            os.remove(pdf_path)
        else:
            logging.warning(f"Could not salvage text from {filename}. Moving to unsalvageable.")
            shutil.move(pdf_path, os.path.join(UNSALVAGEABLE_DIR, filename))

    except subprocess.TimeoutExpired:
        logging.error(f"pdftotext timed out for {filename}. Moving to unsalvageable.")
        shutil.move(pdf_path, os.path.join(UNSALVAGEABLE_DIR, filename))
    except Exception as e:
        logging.error(f"An error occurred during salvage of {filename}: {e}")
        shutil.move(pdf_path, os.path.join(UNSALVAGEABLE_DIR, filename))

def main():
    init_database()
    os.makedirs(SALVAGED_OUTPUT_DIR, exist_ok=True)
    os.makedirs(UNSALVAGEABLE_DIR, exist_ok=True)
    
    while True:
        logging.info("--- Topic Puller starting new cycle ---")
        
        # --- Task 1: Main Library Processing ---
        logging.info("Checking main library for unprocessed EPUBs...")
        books_to_process = get_unprocessed_books()
        if books_to_process:
            logging.info(f"Found {len(books_to_process)} new EPUBs to process.")
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                executor.map(pull_topics_from_book, books_to_process)
            logging.info("Finished processing library batch.")
        else:
            logging.info("No new EPUBs to process in the main library.")

        # --- Task 2: Discard Bin Salvage Operation ---
        logging.info("Checking discard bin for PDFs to salvage...")
        discarded_pdfs = []
        if os.path.exists(DISCARD_BIN):
             discarded_pdfs = [os.path.join(DISCARD_BIN, f) for f in os.listdir(DISCARD_BIN) if f.lower().endswith('.pdf')]
        
        if discarded_pdfs:
            logging.info(f"Found {len(discarded_pdfs)} PDFs in the discard bin to salvage.")
            # Process one by one for stability
            for pdf_file in discarded_pdfs:
                salvage_pdf(pdf_file)
            logging.info("Finished salvaging PDFs from discard bin.")
        else:
            logging.info("No new PDFs found in the discard bin.")

        logging.info("--- Cycle finished. Waiting 5 minutes... ---")
        time.sleep(5 * 60)

if __name__ == "__main__":
    main()
