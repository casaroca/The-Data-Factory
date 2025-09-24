import os
import time
import logging
import sqlite3
import random
from datasets import load_dataset
from concurrent.futures import ThreadPoolExecutor

# --- Configuration ---
LOG_DIR = "/factory/logs"
DB_PATH = "/factory/db/public_dataset_log.db"
RAW_DUMP_DIR = "/factory/data/raw/huggingface_datasets"
MAX_WORKERS = 8 # Increased from 4
REST_PERIOD_SECONDS = 60 * 5 # 5 minutes

# Curated list of confirmed working datasets
DATASETS_TO_PROCESS = {
    "ag_news": (None, "train[:10000]"),
    "imdb": (None, "train[:10000]"),
    "yelp_review_full": (None, "train[:8000]"),
    "amazon_polarity": (None, "train[:8000]"),
    "rotten_tomatoes": (None, "train[:8000]"),
    "tweet_eval_emotion": ("emotion", "train[:5000]"),
    "tweet_eval_hate": ("hate", "train[:5000]"),
    "tweet_eval_offensive": ("offensive", "train[:5000]"),
    "tweet_eval_sentiment": ("sentiment", "train[:5000]"),
    "glue_cola": ("cola", "train[:8000]"),
    "glue_sst2": ("sst2", "train[:8000]"),
    "glue_mrpc": ("mrpc", "train[:5000]"),
    "poem_sentiment": (None, "train[:5000]"),
    "emotion": (None, "train[:8000]"),
}

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'public_dataset_harvester_v2.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())
logging.getLogger("datasets").setLevel(logging.ERROR)

def init_database():
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute('CREATE TABLE IF NOT EXISTS processed_datasets (name TEXT PRIMARY KEY, processed_date TEXT)')
        conn.commit()

def is_dataset_processed(dataset_name):
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("SELECT 1 FROM processed_datasets WHERE name=?", (dataset_name,))
        return c.fetchone() is not None

def mark_dataset_as_processed(dataset_name):
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute("INSERT OR IGNORE INTO processed_datasets VALUES (?, ?)", (dataset_name, time.strftime('%Y-%m-%d %H:%M:%S')))
        conn.commit()

def extract_text_from_record(record):
    """Extract text content from a dataset record"""
    text_keys = ['text', 'review', 'sentence', 'premise', 'hypothesis', 'question', 'content']
    for key in text_keys:
        if key in record and isinstance(record[key], str) and len(record[key].strip()) > 10:
            return record[key].strip()
    if 'sentence1' in record and 'sentence2' in record:
        s1 = str(record['sentence1']) if record['sentence1'] else ""
        s2 = str(record['sentence2']) if record['sentence2'] else ""
        if s1 or s2:
            return f"Sentence 1: {s1}\nSentence 2: {s2}".strip()
    for key, value in record.items():
        if isinstance(value, str) and len(value.strip()) > 15:
            return value.strip()
    return ""

def process_dataset(dataset_info):
    dataset_name, (config, split) = dataset_info
    try:
        if is_dataset_processed(dataset_name):
            logging.info(f"Skipping already processed dataset: {dataset_name}")
            return
        logging.info(f"Processing dataset: {dataset_name} (config: {config}, split: {split})")

        if dataset_name.startswith("tweet_eval_"):
            task = config if config else dataset_name.split("tweet_eval_")[1]
            dataset = load_dataset("tweet_eval", task, split=split)
        elif dataset_name.startswith("glue_"):
            task = config if config else dataset_name.split("glue_")[1]
            dataset = load_dataset("glue", task, split=split)
        else:
            dataset = load_dataset(dataset_name, config, split=split)

        output_dir = os.path.join(RAW_DUMP_DIR, dataset_name)
        os.makedirs(output_dir, exist_ok=True)
        count = 0
        
        for record in dataset:
            text_content = extract_text_from_record(record)
            if text_content and len(text_content) > 20:
                filename = f"{dataset_name}_{config or 'default'}_{count:06d}.txt"
                output_path = os.path.join(output_dir, filename)
                with open(output_path, 'w', encoding='utf-8') as f:
                    f.write(text_content)
                count += 1
        
        if count > 0:
            logging.info(f"Successfully saved {count} text files from dataset: {dataset_name}")
            mark_dataset_as_processed(dataset_name)
        else:
            logging.warning(f"No usable text found in dataset: {dataset_name}")

    except Exception as e:
        logging.error(f"Failed to process dataset {dataset_name}: {e}")

def main():
    init_database()
    while True:
        logging.info("---" + "Starting new Public Dataset Harvester cycle" + "---")
        unprocessed_datasets = {name: config for name, config in DATASETS_TO_PROCESS.items() if not is_dataset_processed(name)}
        if unprocessed_datasets:
            datasets_to_process = random.sample(list(unprocessed_datasets.items()), min(len(unprocessed_datasets), 2))
            logging.info(f"Selected datasets for this cycle: {', '.join([d[0] for d in datasets_to_process])}")
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                executor.map(process_dataset, datasets_to_process)
        else:
            logging.info("All configured datasets have been processed. Harvester is idle.")
        
        logging.info(f"---" + "Cycle finished. Waiting " + "%d seconds..." % REST_PERIOD_SECONDS + "---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()
