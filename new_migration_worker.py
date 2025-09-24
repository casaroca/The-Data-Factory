import os
import shutil
import logging
import sys

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

SOURCE_DIR = "/factory/data/archive/raw"
DESTINATION_DIR = "/mnt/archive"

def migrate_data():
    logging.info(f"Starting data migration from {SOURCE_DIR} to {DESTINATION_DIR}")

    if not os.path.exists(SOURCE_DIR):
        logging.error(f"Source directory {SOURCE_DIR} does not exist. Exiting.")
        sys.exit(1)

    if not os.path.exists(DESTINATION_DIR):
        logging.info(f"Destination directory {DESTINATION_DIR} does not exist. Creating it.")
        try:
            os.makedirs(DESTINATION_DIR)
        except OSError as e:
            logging.error(f"Error creating destination directory {DESTINATION_DIR}: {e}")
            sys.exit(1)

    files_to_migrate = []
    logging.info(f"Starting to scan source directory: {SOURCE_DIR}")
    try:
        for root, _, files in os.walk(SOURCE_DIR):
            for file_name in files:
                source_file_path = os.path.join(root, file_name)
                relative_path = os.path.relpath(root, SOURCE_DIR)
                destination_root = os.path.join(DESTINATION_DIR, relative_path)
                destination_file_path = os.path.join(destination_root, file_name)
                files_to_migrate.append((source_file_path, destination_file_path, destination_root))
    except Exception as e:
        logging.error(f"Error during directory scan with os.walk: {e}")
        sys.exit(1)

    logging.info(f"Finished scanning. Found {len(files_to_migrate)} files to migrate.")

    for source_file_path, destination_file_path, destination_root in files_to_migrate:
        if not os.path.exists(destination_root):
            try:
                os.makedirs(destination_root)
                logging.info(f"Created directory: {destination_root}")
            except OSError as e:
                logging.error(f"Error creating directory {destination_root}: {e}. Skipping file {source_file_path}")
                continue

        # More robust check before moving
        if os.path.exists(source_file_path) and os.path.isfile(source_file_path) and os.access(source_file_path, os.R_OK):
            try:
                logging.info(f"Attempting to move file: {source_file_path} to {destination_file_path}")
                shutil.move(source_file_path, destination_file_path)
            except Exception as e:
                logging.error(f"Failed to move file {source_file_path}: {e}")
        else:
            logging.warning(f"File not found, not a regular file, or not readable, skipping: {source_file_path}")


    # After moving all files, attempt to remove empty directories in the source
    # This needs to be done in reverse order (bottom-up) to avoid errors
    for root, dirs, files in os.walk(SOURCE_DIR, topdown=False):
        if not os.listdir(root): # Check if directory is empty
            try:
                os.rmdir(root)
                logging.info(f"Removed empty source directory: {root}")
            except OSError as e:
                logging.warning(f"Could not remove directory {root} (might not be empty or permissions issue): {e}")

    logging.info("Data migration completed.")

if __name__ == "__main__":
    migrate_data()