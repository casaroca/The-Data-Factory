import os
import time
import logging
import re
import shutil
import spacy
from detoxify import Detoxify
from concurrent.futures import ThreadPoolExecutor

# --- Configuration ---
LOG_DIR = "/factory/logs"
INBOX_DIR = "/factory/data/raw_sort"
PROCESSED_DIR = "/factory/data/processed_clean"
DISCARDED_DIR = "/factory/data/discarded/unsafe_content"
MAX_WORKERS = 10 # Tuned for a multi-core server
BATCH_SIZE = 100
TOXICITY_THRESHOLD = 0.8 # Discard if toxicity score is > 80%

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'ethical_sorter.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

# --- Load AI Models ---
try:
    logging.info("Loading spaCy NLP model for PII redaction...")
    NLP = spacy.load("en_core_web_sm")
    logging.info("Loading Detoxify model for SFW guardrails...")
    SFW_MODEL = Detoxify('unbiased')
    logging.info("AI models loaded successfully.")
except Exception as e:
    logging.error(f"Could not load AI models: {e}")
    NLP = None
    SFW_MODEL = None

def is_safe_for_work(text):
    """Uses an AI model to check if text is safe for work."""
    if not SFW_MODEL:
        logging.warning("SFW model not loaded. Skipping safety check.")
        return True
    try:
        results = SFW_MODEL.predict(text)
        # Check if any toxicity category is above the threshold
        if any(score > TOXICITY_THRESHOLD for score in results.values()):
            logging.warning(f"Content failed SFW check. Scores: {results}")
            return False
        return True
    except Exception as e:
        logging.error(f"SFW check failed: {e}")
        return True # Default to safe if the model fails

def redact_pii(text):
    """Redacts sensitive information but keeps names for citations."""
    # Redact email addresses
    text = re.sub(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}', '[REDACTED_EMAIL]', text)
    # Redact phone numbers (North American format)
    text = re.sub(r'(\d{3}[-\.\s]??\d{3}[-\.\s]??\d{4}|\(\d{3}\)\s*\d{3}[-\.\s]??\d{4}|\d{3}[-\.\s]??\d{4})', '[REDACTED_PHONE]', text)
    
    # Use spaCy for more advanced redaction if available
    if not NLP:
        return text
    
    doc = NLP(text)
    redacted_text = list(text)
    # Redact locations but keep people's names
    for ent in reversed(doc.ents):
        if ent.label_ in ["GPE", "LOC", "FAC"]: # GPE=Geopolitical, LOC=Location, FAC=Facility
            redacted_text[ent.start_char:ent.end_char] = f"[REDACTED_{ent.label_}]"
            
    return "".join(redacted_text)

def process_file(filepath):
    """Full processing pipeline for a single file."""
    filename = os.path.basename(filepath)
    try:
        logging.info(f"Sorting file: {filename}")
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()

        # 1. SFW Guardrail Check
        if not is_safe_for_work(content):
            shutil.move(filepath, os.path.join(DISCARDED_DIR, filename))
            logging.warning(f"Moved unsafe file to discard bin: {filename}")
            return

        # 2. PII Redaction
        redacted_content = redact_pii(content)

        # 3. Determine output category and save
        source_category = os.path.basename(os.path.dirname(filepath))
        output_category_dir = os.path.join(PROCESSED_DIR, source_category)
        os.makedirs(output_category_dir, exist_ok=True)
        output_path = os.path.join(output_category_dir, filename)

        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(redacted_content)
        
        logging.info(f"Successfully sorted and saved to: {output_path}")
        os.remove(filepath) # Remove original after success

    except Exception as e:
        logging.error(f"Failed to process file {filename}: {e}")
        # Move to a different discard bin on critical failure
        error_bin = os.path.join(DISCARDED_DIR, "processing_errors")
        os.makedirs(error_bin, exist_ok=True)
        shutil.move(filepath, os.path.join(error_bin, filename))

def main():
    if not NLP or not SFW_MODEL:
        logging.critical("A required AI model failed to load. The sorter cannot start.")
        return

    while True:
        logging.info("Ethical Sorter is checking for new files...")
        all_files = [os.path.join(dp, f) for dp,_,fns in os.walk(INBOX_DIR) for f in fns]
        
        if all_files:
            batch_to_process = all_files[:BATCH_SIZE]
            logging.info(f"Found {len(all_files)} files to sort. Processing a batch of {len(batch_to_process)}.")
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                executor.map(process_file, batch_to_process)
            logging.info("Batch finished. Immediately checking for more...")
        else:
            logging.info("No new files to sort. Waiting...")
            time.sleep(20)

if __name__ == "__main__":
    main()