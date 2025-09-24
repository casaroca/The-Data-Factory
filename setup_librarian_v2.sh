#!/bin/bash
set -e

echo "--- Setting up Consolidated Librarian v2 ---"

# --- 1. Stop and remove the old librarian services ---
echo "[+] Stopping and removing old librarian and jr_librarian services..."
sudo systemctl stop librarian jr_librarian || true
sudo systemctl disable librarian jr_librarian || true
sudo rm -f /etc/systemd/system/librarian.service
sudo rm -f /etc/systemd/system/jr_librarian.service
sudo rm -rf /factory/workers/organizers/librarian
sudo rm -rf /factory/workers/organizers/jr_librarian
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/organizers/librarian_v2"
LOG_DIR="/factory/logs"
DB_PATH="/factory/db/library.db"
# Scan both directories for files
SCAN_DIRS=("/library/book_deposit" "/library/discarded")
LIBRARY_DIR="/factory/library/library"
ERROR_DIR="/factory/library/discarded" # Failed conversions still go here
MEDIA_DIR="/factory/library/media_for_processing"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $MEDIA_DIR

# --- 4. Create Application Files ---
echo "[+] Creating librarian_v2.py application file..."
cat << 'EOF' > $PROJECT_DIR/librarian_v2.py
import os
import time
import logging
import re
import subprocess
import shutil
import sqlite3
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor

# --- Configuration ---
LOG_DIR = "/factory/logs"
DB_PATH = "/factory/db/library.db"
SCAN_DIRS = ["/library/book_deposit", "/library/discarded"]
LIBRARY_DIR = "/factory/library/library"
ERROR_DIR = "/factory/library/discarded"
MEDIA_DIR = "/factory/library/media_for_processing"
MAX_WORKERS = 15
BATCH_SIZE = 50
CONVERT_EXTENSIONS = ['.txt', '.pdf', '.mobi', '.html', '.docx']
DIRECT_PROCESS_EXTENSIONS = ['.epub']
MEDIA_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.gif', '.mp3', '.wav', '.mp4', '.mov']

# --- Setup Logging ---
logging.basicConfig(filename=os.path.join(LOG_DIR, 'librarian_v2.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def init_database():
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute('CREATE TABLE IF NOT EXISTS books (id INTEGER PRIMARY KEY,title TEXT,author TEXT,category TEXT,filepath TEXT UNIQUE,added_date TEXT)')
        conn.commit()

def convert_to_epub(input_path):
    output_filename = os.path.splitext(os.path.basename(input_path))[0] + ".epub"
    temp_output_path = os.path.join("/tmp", output_filename)
    cmd = ['/opt/calibre/ebook-convert', input_path, temp_output_path, '--enable-heuristics']
    result = subprocess.run(cmd, capture_output=True, text=True, errors='ignore', timeout=900)
    if result.returncode != 0:
        raise Exception(f"Calibre conversion failed: {result.stderr}")
    return temp_output_path

def get_metadata(epub_path):
    cmd = ['/opt/calibre/ebook-meta', epub_path]
    result = subprocess.run(cmd, capture_output=True, text=True, errors='ignore')
    if result.returncode != 0:
        return {'title': os.path.splitext(os.path.basename(epub_path))[0]}
    return {k.strip().lower(): v.strip() for k, v in (line.split(":", 1) for line in result.stdout.splitlines() if ":" in line)}

def categorize_book(metadata):
    tags = metadata.get('tags', '').lower()
    if any(g in tags for g in ['fiction', 'novel']): return "Fiction"
    return "Unsorted"

def file_book(epub_path, original_filepath):
    """Takes a path to an EPUB, gets metadata, categorizes, and moves it to the final library."""
    try:
        metadata = get_metadata(epub_path)
        category = categorize_book(metadata)
        category_dir = os.path.join(LIBRARY_DIR, category)
        os.makedirs(category_dir, exist_ok=True)
        
        final_path = os.path.join(category_dir, os.path.basename(epub_path))
        shutil.move(epub_path, final_path)
        
        with sqlite3.connect(DB_PATH) as conn:
            c = conn.cursor()
            c.execute('INSERT OR IGNORE INTO books(title,author,category,filepath,added_date)VALUES(?,?,?,?,?)',
                      (metadata.get('title', 'Unknown'), metadata.get('author(s)', 'Unknown'), category, final_path, datetime.now().isoformat()))
            conn.commit()
        
        logging.info(f"Successfully filed '{metadata.get('title')}'")
        # Remove original file if it's different from the EPUB path (i.e., it was converted)
        if original_filepath != epub_path and os.path.exists(original_filepath):
            os.remove(original_filepath)

    except Exception as e:
        logging.error(f"Failed to file book from {original_filepath}: {e}")
        # If filing fails, move the original file to the error directory
        if os.path.exists(original_filepath):
            shutil.move(original_filepath, os.path.join(ERROR_DIR, os.path.basename(original_filepath)))
        # Clean up temp epub if it exists
        if os.path.dirname(epub_path) == "/tmp" and os.path.exists(epub_path):
            os.remove(epub_path)

def process_file(filepath):
    """Determines how to handle a file based on its extension."""
    ext = os.path.splitext(filepath)[1].lower()
    
    if ext in CONVERT_EXTENSIONS:
        logging.info(f"Converting: {os.path.basename(filepath)}")
        try:
            epub_path = convert_to_epub(filepath)
            file_book(epub_path, original_filepath=filepath)
        except Exception as e:
            logging.error(f"Failed to convert {os.path.basename(filepath)}: {e}")
            shutil.move(filepath, os.path.join(ERROR_DIR, os.path.basename(filepath)))
            
    elif ext in DIRECT_PROCESS_EXTENSIONS:
        logging.info(f"Processing EPUB: {os.path.basename(filepath)}")
        # For EPUBs, the original path is the same as the epub path
        file_book(filepath, original_filepath=filepath)

def move_media_file(filepath):
    try:
        os.makedirs(MEDIA_DIR, exist_ok=True)
        shutil.move(filepath, os.path.join(MEDIA_DIR, os.path.basename(filepath)))
        logging.info(f"Moved media file: {os.path.basename(filepath)}")
    except Exception as e:
        logging.error(f"Could not move media file {filepath}: {e}")

def cleanup_empty_dirs(root_dir):
    for dirpath, dirnames, filenames in os.walk(root_dir, topdown=False):
        if not dirnames and not filenames and os.path.realpath(dirpath) != os.path.realpath(root_dir):
            try:
                os.rmdir(dirpath)
                logging.info(f"Removed empty directory: {dirpath}")
            except OSError: pass

def main():
    init_database()
    while True:
        logging.info("--- Librarian v2 starting new cycle ---")
        
        files_to_process = []
        media_files = []
        
        for scan_dir in SCAN_DIRS:
            if os.path.exists(scan_dir):
                for dirpath, _, filenames in os.walk(scan_dir):
                    for filename in filenames:
                        filepath = os.path.join(dirpath, filename)
                        ext = os.path.splitext(filename)[1].lower()
                        
                        if ext in CONVERT_EXTENSIONS or ext in DIRECT_PROCESS_EXTENSIONS:
                            files_to_process.append(filepath)
                        elif ext in MEDIA_EXTENSIONS:
                            media_files.append(filepath)
        
        if files_to_process:
            batch = files_to_process[:BATCH_SIZE]
            logging.info(f"Found {len(files_to_process)} books to process. Running a batch of {len(batch)}.")
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                executor.map(process_file, batch)
        
        if media_files:
            logging.info(f"Found {len(media_files)} media files to move.")
            for media_file in media_files:
                move_media_file(media_file)

        # Always run cleanup after a cycle
        for scan_dir in SCAN_DIRS:
            cleanup_empty_dirs(scan_dir)

        if not files_to_process and not media_files:
            logging.info("No new files found. Waiting...")
            time.sleep(30)

if __name__ == "__main__":
    main()
EOF

cat << 'EOF' > $PROJECT_DIR/requirements.txt
# No external packages needed
EOF

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/librarian_v2.service
[Unit]
Description=Librarian Service v2
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 librarian_v2.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting Librarian v2 service..."
sudo chown -R $USER:$USER /factory
sudo systemctl daemon-reload
sudo systemctl start librarian_v2
sudo systemctl enable librarian_v2

echo "--- Librarian v2 Setup Complete ---"
echo "To check the status, run: sudo systemctl status librarian_v2"
echo "To watch the logs, run: tail -f /factory/logs/librarian_v2.log"
