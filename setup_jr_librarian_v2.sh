#!/bin/bash
set -e

echo "--- Setting up Jr. Librarian (with Advanced Salvage) ---"

# --- 1. Stop and remove the old service ---
echo "[+] Stopping and removing old jr_librarian service..."
sudo systemctl stop jr_librarian || true
sudo systemctl disable jr_librarian || true
sudo rm -f /etc/systemd/system/jr_librarian.service
sudo rm -rf /factory/workers/organizers/jr_librarian
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/organizers/jr_librarian"
LOG_DIR="/factory/logs"
DB_PATH="/factory/db/library.db"
INBOX_DIR="/factory/library/book_deposit"
LIBRARY_DIR="/factory/library/library"
DISCARD_BIN="/factory/library/discarded"
UNSALVAGEABLE_DIR="/factory/library/unsalvageable"
MEDIA_DIR="/factory/library/media_for_processing"
HTML_DIR="/factory/data/raw/html_from_library"
SALVAGED_TEXT_DIR="/factory/data/raw/salvaged_text"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $MEDIA_DIR
mkdir -p $HTML_DIR
mkdir -p $UNSALVAGEABLE_DIR
mkdir -p $SALVAGED_TEXT_DIR

# --- 4. Create Application Files ---
echo "[+] Creating jr_librarian.py application file..."
cat << 'EOF' > $PROJECT_DIR/jr_librarian.py
import os
import time
import logging
import re
import subprocess
import shutil
import sqlite3
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor
from collections import defaultdict

# --- Configuration ---
LOG_DIR = "/factory/logs"
DB_PATH = "/factory/db/library.db"
INBOX_DIR = "/factory/library/book_deposit"
LIBRARY_DIR = "/factory/library/library"
DISCARD_BIN = "/factory/library/discarded"
UNSALVAGEABLE_DIR = "/factory/library/unsalvageable"
MEDIA_DIR = "/factory/library/media_for_processing"
HTML_DIR = "/factory/data/raw/html_from_library"
SALVAGED_TEXT_DIR = "/factory/data/raw/salvaged_text"
MAX_WORKERS = 10
BATCH_SIZE = 50
BOOK_EXTENSIONS = ['.epub']
MEDIA_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.gif', '.mp3', '.wav', '.mp4', '.mov', '.avi']
HTML_EXTENSIONS = ['.html', '.htm']
SALVAGE_EXTENSIONS = ['.pdf', '.mobi']
MIN_PDF_SIZE_KB = 4

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'jr_librarian.log'), level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

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

def process_epub_file(filepath):
    """Processes a single EPUB file."""
    try:
        logging.info(f"Processing EPUB: {os.path.basename(filepath)}")
        metadata = get_metadata(filepath)
        category = categorize_book(metadata)
        category_dir = os.path.join(LIBRARY_DIR, category)
        os.makedirs(category_dir, exist_ok=True)
        final_path = os.path.join(category_dir, os.path.basename(filepath))
        shutil.move(filepath, final_path)
        with sqlite3.connect(DB_PATH) as conn:
            c = conn.cursor()
            c.execute('INSERT OR IGNORE INTO books (title, author, category, filepath, added_date) VALUES (?,?,?,?,?)',
                      (metadata.get('title', 'Unknown'), metadata.get('author(s)', 'Unknown'), category, final_path, datetime.now().isoformat()))
            conn.commit()
        logging.info(f"Successfully filed '{metadata.get('title')}'")
    except Exception as e:
        logging.error(f"Failed to process EPUB {os.path.basename(filepath)}: {e}")
        # On failure, move it back to discard bin to avoid loops
        shutil.move(filepath, os.path.join(DISCARD_BIN, os.path.basename(filepath)))

def salvage_file(filepath):
    """Attempts a two-stage salvage: first to EPUB, then fallback to TXT."""
    filename = os.path.basename(filepath)
    try:
        # Stage 1: Try to convert to a high-quality EPUB
        logging.info(f"Attempting to salvage '{filename}' to EPUB...")
        epub_output_filename = os.path.splitext(filename)[0] + ".epub"
        epub_output_path = os.path.join(INBOX_DIR, epub_output_filename)
        cmd_epub = ['/opt/calibre/ebook-convert', filepath, epub_output_path, '--enable-heuristics']
        result_epub = subprocess.run(cmd_epub, capture_output=True, text=True, errors='ignore', timeout=600)
        
        if result_epub.returncode == 0:
            logging.info(f"Successfully salvaged '{filename}' to EPUB. It will be processed in the next cycle.")
            os.remove(filepath)
            return

        # Stage 2: If EPUB fails, fall back to raw text extraction
        logging.warning(f"EPUB salvage failed for '{filename}'. Attempting raw text extraction...")
        txt_output_filename = os.path.splitext(filename)[0] + ".txt"
        txt_output_path = os.path.join(SALVAGED_TEXT_DIR, txt_output_filename)
        cmd_txt = ['/usr/bin/pdftotext', filepath, txt_output_path] if filepath.lower().endswith('.pdf') else ['/opt/calibre/ebook-convert', filepath, txt_output_path]
        
        result_txt = subprocess.run(cmd_txt, capture_output=True, text=True, errors='ignore', timeout=300)

        if result_txt.returncode == 0 and os.path.exists(txt_output_path) and os.path.getsize(txt_output_path) > 100:
            logging.info(f"Successfully salvaged raw text from '{filename}'.")
            os.remove(filepath)
        else:
            raise Exception(f"Both EPUB and TXT salvage failed. Final error: {result_txt.stderr or result_epub.stderr}")

    except Exception as e:
        logging.error(f"Could not salvage {filename}: {e}")
        shutil.move(filepath, os.path.join(UNSALVAGEABLE_DIR, filename))

def move_file(filepath, dest_dir, file_type):
    """Generic function to move files."""
    try:
        logging.info(f"Moving {file_type} file: {os.path.basename(filepath)}")
        os.makedirs(dest_dir, exist_ok=True)
        shutil.move(filepath, os.path.join(dest_dir, os.path.basename(filepath)))
    except Exception as e:
        logging.error(f"Could not move {file_type} file {filepath}: {e}")

def cleanup_empty_dirs(root_dir):
    for dirpath, _, _ in os.walk(root_dir, topdown=False):
        # Check if directory is empty
        if not os.listdir(dirpath):
            # Check if it's not the root directory itself
            if os.path.realpath(dirpath) != os.path.realpath(root_dir):
                try:
                    os.rmdir(dirpath)
                    logging.info(f"Removed empty directory: {dirpath}")
                except OSError: pass

def main():
    while True:
        logging.info("Jr. Librarian is checking for all processable files...")
        tasks = defaultdict(list)
        scan_dirs = [INBOX_DIR, DISCARD_BIN]

        for directory in scan_dirs:
            for dirpath, _, filenames in os.walk(directory):
                for filename in filenames:
                    filepath = os.path.join(dirpath, filename)
                    ext = os.path.splitext(filename)[1].lower()
                    
                    # Rule: Delete small PDFs first
                    if ext == '.pdf' and os.path.getsize(filepath) < MIN_PDF_SIZE_KB * 1024:
                        logging.warning(f"Deleting small PDF: {filename}")
                        os.remove(filepath)
                        continue

                    if ext in BOOK_EXTENSIONS and directory == INBOX_DIR: tasks['epubs'].append(filepath)
                    elif ext in MEDIA_EXTENSIONS and directory == INBOX_DIR: tasks['media'].append(filepath)
                    elif ext in HTML_EXTENSIONS and directory == INBOX_DIR: tasks['html'].append(filepath)
                    elif ext in SALVAGE_EXTENSIONS and directory == DISCARD_BIN: tasks['salvage'].append(filepath)
        
        if tasks['epubs']:
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                executor.map(process_epub_file, tasks['epubs'][:BATCH_SIZE])
        
        if tasks['media']:
            for media_file in tasks['media']: move_file(media_file, MEDIA_DIR, "media")

        if tasks['html']:
            for html_file in tasks['html']: move_file(html_file, HTML_DIR, "HTML")

        if tasks['salvage']:
            logging.info(f"Found {len(tasks['salvage'])} files to salvage from discard bin.")
            with ThreadPoolExecutor(max_workers=4) as executor: # Salvage is slower, use fewer workers
                executor.map(salvage_file, tasks['salvage'][:10])

        cleanup_empty_dirs(INBOX_DIR)
        cleanup_empty_dirs(DISCARD_BIN)

        if not any(tasks.values()):
            logging.info("No new files found. Waiting...")
            time.sleep(30)

if __name__ == "__main__":
    from collections import defaultdict
    main()
EOF

cat << 'EOF' > $PROJECT_DIR/requirements.txt
# No external pip packages needed
EOF

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/jr_librarian.service
[Unit]
Description=Jr. Librarian Service (with Salvage)
After=network-online.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 jr_librarian.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting Jr. Librarian service..."
sudo chown -R $USER:$USER $PROJECT_DIR $MEDIA_DIR $HTML_DIR $UNSALVAGEABLE_DIR $SALVAGED_TEXT_DIR
sudo systemctl daemon-reload
sudo systemctl start jr_librarian
sudo systemctl enable jr_librarian

echo "--- Jr. Librarian Setup Complete ---"
echo "To check the status, run: sudo systemctl status jr_librarian"
echo "To watch the logs, run: tail -f /factory/logs/jr_librarian.log"

