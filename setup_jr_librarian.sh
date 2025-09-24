#!/bin/bash
set -e

echo "--- Setting up Jr. Librarian (Updated PDF & MOBI handling) ---"

# --- 1. Define Paths ---
PROJECT_DIR="/factory/workers/organizers/jr_librarian"
LOG_DIR="/factory/logs"
DB_PATH="/factory/db/library.db"
INBOX_DIR="/factory/library/book_deposit"
LIBRARY_DIR="/factory/library/library"
ERROR_DIR="/factory/library/discarded"
MEDIA_DIR="/factory/library/media_for_processing"
HTML_DIR="/factory/data/raw/html_from_library"
PDF_TEXT_DIR="/factory/data/raw/pdf_extracts"
USER="tdf"

# --- 2. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $MEDIA_DIR
mkdir -p $HTML_DIR
mkdir -p $PDF_TEXT_DIR

# --- 3. Create Application Files ---
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

# --- Configuration ---
LOG_DIR = "/factory/logs"
DB_PATH = "/factory/db/library.db"
SCAN_DIRS = ["/factory/library/book_deposit", "/factory/library/discarded"]
LIBRARY_DIR = "/factory/library/library"
ERROR_DIR = "/factory/library/discarded"
MEDIA_DIR = "/factory/library/media_for_processing"
HTML_DIR = "/factory/data/raw/html_from_library"
PDF_TEXT_DIR = "/factory/data/raw/pdf_extracts"
MAX_WORKERS = 10
BATCH_SIZE = 50
BOOK_EXTENSIONS = ['.epub']
MEDIA_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.gif', '.mp3', '.wav', '.mp4', '.mov', '.avi']
HTML_EXTENSIONS = ['.html', '.htm']
PDF_EXTENSIONS = ['.pdf']
MOBI_EXTENSIONS = ['.mobi']

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
        os.makedirs(ERROR_DIR, exist_ok=True)
        shutil.move(filepath, os.path.join(ERROR_DIR, os.path.basename(filepath)))

def process_pdf_file(filepath):
    """Extracts text from a PDF and sends it to the raw data pipeline."""
    try:
        filename = os.path.basename(filepath)
        # 1. Check file size and delete if too small
        if os.path.getsize(filepath) <= 4096:
            logging.info(f"Deleting small PDF: {filename}")
            os.remove(filepath)
            return

        logging.info(f"Extracting text from PDF: {filename}")
        # 2. Extract text using pdftotext
        output_txt_path = os.path.join(PDF_TEXT_DIR, os.path.splitext(filename)[0] + ".txt")
        subprocess.run(['pdftotext', '-layout', filepath, output_txt_path], check=True)
        
        # 3. Verify text was extracted
        if os.path.exists(output_txt_path) and os.path.getsize(output_txt_path) > 100:
             logging.info(f"Successfully extracted text from {filename}")
             os.remove(filepath) # Delete original PDF after success
        else:
             logging.warning(f"No text extracted from {filename}, moving to discarded.")
             shutil.move(filepath, os.path.join(ERROR_DIR, filename))

    except Exception as e:
        logging.error(f"Failed to process PDF {os.path.basename(filepath)}: {e}")
        shutil.move(filepath, os.path.join(ERROR_DIR, os.path.basename(filepath)))

def handle_mobi_file(filepath):
    """Moves a MOBI file from discarded back to the book deposit for reconversion."""
    try:
        filename = os.path.basename(filepath)
        logging.info(f"Moving MOBI file for reconversion: {filename}")
        shutil.move(filepath, os.path.join("/factory/library/book_deposit", filename))
    except Exception as e:
        logging.error(f"Could not move MOBI file {filepath}: {e}")

def move_media_file(filepath):
    """Moves a media file to the designated processing folder."""
    try:
        filename = os.path.basename(filepath)
        logging.info(f"Found media file, moving: {filename}")
        os.makedirs(MEDIA_DIR, exist_ok=True)
        shutil.move(filepath, os.path.join(MEDIA_DIR, filename))
    except Exception as e:
        logging.error(f"Could not move media file {filepath}: {e}")

def move_html_file(filepath):
    """Moves an HTML file to the raw data directory for the sorter."""
    try:
        filename = os.path.basename(filepath)
        logging.info(f"Found HTML file, moving to raw data: {filename}")
        os.makedirs(HTML_DIR, exist_ok=True)
        shutil.move(filepath, os.path.join(HTML_DIR, filename))
    except Exception as e:
        logging.error(f"Could not move HTML file {filepath}: {e}")

def cleanup_empty_dirs(root_dir):
    """Removes empty subdirectories."""
    for dirpath, dirnames, filenames in os.walk(root_dir, topdown=False):
        if not dirnames and not filenames and os.path.realpath(dirpath) != os.path.realpath(root_dir):
            try:
                os.rmdir(dirpath)
                logging.info(f"Removed empty directory: {dirpath}")
            except OSError: pass

def main():
    while True:
        logging.info("Jr. Librarian is checking for all processable files...")
        all_epubs, all_media, all_html, all_pdfs, all_mobis = [], [], [], [], []
        
        for scan_dir in SCAN_DIRS:
            if os.path.exists(scan_dir):
                for dirpath, _, filenames in os.walk(scan_dir):
                    for filename in filenames:
                        filepath = os.path.join(dirpath, filename)
                        ext = os.path.splitext(filename)[1].lower()
                        if ext in BOOK_EXTENSIONS: all_epubs.append(filepath)
                        elif ext in MEDIA_EXTENSIONS: all_media.append(filepath)
                        elif ext in HTML_EXTENSIONS: all_html.append(filepath)
                        elif ext in PDF_EXTENSIONS: all_pdfs.append(filepath)
                        elif ext in MOBI_EXTENSIONS and "discarded" in dirpath: all_mobis.append(filepath)
        
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            if all_epubs: executor.map(process_epub_file, all_epubs)
            if all_pdfs: executor.map(process_pdf_file, all_pdfs)
            if all_mobis: executor.map(handle_mobi_file, all_mobis)
            if all_media: executor.map(move_media_file, all_media)
            if all_html: executor.map(move_html_file, all_html)
        
        for scan_dir in SCAN_DIRS:
            cleanup_empty_dirs(scan_dir)

        if not any([all_epubs, all_media, all_html, all_pdfs, all_mobis]):
            logging.info("No new files found. Waiting...")
            time.sleep(30)

if __name__ == "__main__":
    main()
EOF

cat << 'EOF' > $PROJECT_DIR/requirements.txt
# No external packages needed
EOF

# --- 4. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 5. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/jr_librarian.service
[Unit]
Description=Jr. Librarian Service
After=network.target

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

# --- 6. Start the Service ---
echo "[+] Starting Jr. Librarian service..."
sudo chown -R $USER:$USER /factory
sudo systemctl daemon-reload
sudo systemctl start jr_librarian
sudo systemctl enable jr_librarian

echo "--- Jr. Librarian Setup Complete ---"
echo "To check the status, run: sudo systemctl status jr_librarian"
echo "To watch the logs, run: tail -f /factory/logs/jr_librarian.log"
