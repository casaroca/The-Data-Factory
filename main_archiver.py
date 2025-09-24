import os
import shutil
import logging
import time
import sys

# --- Configuration ---
LOG_DIR = "/factory/logs"
SOURCE_DIR = "/factory/data/raw"
ARCHIVE_COPY_DIR = "/mnt/archive"
DESTINATION_SORT_DIR = "/factory/data/raw_sort"
BATCH_SIZE = 100
SLEEP_SECONDS = 30

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    filename=os.path.join(LOG_DIR, 'main_archiver.log'),
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logging.getLogger('').addHandler(logging.StreamHandler())

def process_file(filepath):
    filename = os.path.basename(filepath)
    # Determine the relative path from SOURCE_DIR to maintain directory structure
    relative_path = os.path.relpath(os.path.dirname(filepath), SOURCE_DIR)

    archive_dest_path = os.path.join(ARCHIVE_COPY_DIR, relative_path, filename)
    sort_dest_path = os.path.join(DESTINATION_SORT_DIR, relative_path, filename)

    try:
        if not os.path.exists(filepath):
            logging.warning(f"File {filepath} not found before processing, skipping.")
            return

        # Ensure destination directories exist
        os.makedirs(os.path.dirname(archive_dest_path), exist_ok=True)
        os.makedirs(os.path.dirname(sort_dest_path), exist_ok=True)

        # 1. Copy to /mnt/archive
        logging.info(f"Copying {filepath} to {archive_dest_path}")
        shutil.copy2(filepath, archive_dest_path) # copy2 preserves metadata

        # 2. Move to /factory/data/raw_sort
        logging.info(f"Moving {filepath} to {sort_dest_path}")
        shutil.move(filepath, sort_dest_path)
        logging.info(f"Successfully processed {filename}")

    except FileNotFoundError:
        logging.warning(f"File {filepath} not found during processing, skipping.")
    except Exception as e:
        logging.error(f"Error processing {filepath}: {e}")
        # Optionally move to an error directory if processing consistently fails

def main():
    # Ensure main directories exist
    os.makedirs(SOURCE_DIR, exist_ok=True)
    os.makedirs(ARCHIVE_COPY_DIR, exist_ok=True)
    os.makedirs(DESTINATION_SORT_DIR, exist_ok=True)

    logging.info("Main Archiver started. Monitoring for new files...")

    while True:
        files_to_process = []
        try:
            # os.walk is efficient for finding files, even in deep structures
            for root, _, files in os.walk(SOURCE_DIR):
                for filename in files:
                    files_to_process.append(os.path.join(root, filename))
        except Exception as e:
            logging.error(f"Error scanning source directory {SOURCE_DIR}: {e}")
            time.sleep(SLEEP_SECONDS)
            continue

        if files_to_process:
            logging.info(f"Found {len(files_to_process)} files in {SOURCE_DIR}. Processing batch...")
            # Process files in batches to avoid overwhelming the system
            for i in range(0, len(files_to_process), BATCH_SIZE):
                batch = files_to_process[i:i + BATCH_SIZE]
                for filepath in batch:
                    process_file(filepath)
            logging.info("Batch processing complete. Checking for more files...")
        else:
            logging.info(f"No new files in {SOURCE_DIR}. Sleeping for {SLEEP_SECONDS} seconds.")
        
        time.sleep(SLEEP_SECONDS)

if __name__ == "__main__":
    main()
