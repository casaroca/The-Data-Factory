#!/bin/bash
set -e

echo "--- Setting up The Librarian (Corrected) ---"

# --- 1. System Prerequisites ---
echo "[+] Installing Calibre for ebook conversion..."
export NEEDRESTART_MODE=a
sudo -v && wget -nv -O- https://download.calibre-ebook.com/linux-installer.sh | sudo sh /dev/stdin

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/organizers/librarian"
# Corrected paths for the new single-drive layout
INBOX_DIR="/factory/library/book_deposit"
LIBRARY_DIR="/factory/library/library"
ERROR_DIR="/factory/library/discarded"
USER="tdf"

# --- 3. Create Project Directory ---
echo "[+] Creating project directory..."
mkdir -p $PROJECT_DIR

# --- 4. Create Application Files ---
echo "[+] Creating Librarian application files..."
cat << 'EOF' > $PROJECT_DIR/librarian.py
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
INBOX_DIR = "/factory/library/book_deposit"
LIBRARY_DIR = "/factory/library/library"
ERROR_DIR = "/factory/library/discarded"
MAX_WORKERS = 15
BATCH_SIZE = 25
VALID_EXTENSIONS = ['.txt', '.pdf', '.mobi', '.azw3', '.epub', '.html', '.docx']

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'librarian.log'), level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def init_database():
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute('''
            CREATE TABLE IF NOT EXISTS books (
                id INTEGER PRIMARY KEY, title TEXT, author TEXT, category TEXT,
                filepath TEXT UNIQUE, added_date TEXT
            )''')
        conn.commit()

def convert_to_epub(input_path):
    output_filename = os.path.splitext(os.path.basename(input_path))[0] + ".epub"
    temp_output_path = os.path.join("/tmp", output_filename)
    
    logging.info(f"Converting {os.path.basename(input_path)} with heuristic processing...")
    cmd = ['/opt/calibre/ebook-convert', input_path, temp_output_path, '--enable-heuristics']
    result = subprocess.run(cmd, capture_output=True, text=True, errors='ignore', timeout=900)
    
    if result.returncode != 0:
        raise Exception(f"Calibre conversion failed: {result.stderr}")
    
    logging.info(f"Successfully converted to {os.path.basename(temp_output_path)}")
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
    if any(g in tags for g in ['science', 'mathematics']): return "Science"
    return "Unsorted"

def process_new_book(filepath):
    original_filename = os.path.basename(filepath)
    try:
        epub_path = convert_to_epub(filepath)
        metadata = get_metadata(epub_path)
        category = categorize_book(metadata)
        
        category_dir = os.path.join(LIBRARY_DIR, category)
        os.makedirs(category_dir, exist_ok=True)
        final_path = os.path.join(category_dir, os.path.basename(epub_path))
        
        shutil.move(epub_path, final_path)
        
        with sqlite3.connect(DB_PATH) as conn:
            c = conn.cursor()
            c.execute('INSERT OR IGNORE INTO books (title, author, category, filepath, added_date) VALUES (?,?,?,?,?)',
                      (metadata.get('title', 'Unknown'), metadata.get('author(s)', 'Unknown'), category, final_path, datetime.now().isoformat()))
            conn.commit()
        logging.info(f"Successfully registered '{metadata.get('title')}'")
        
        os.remove(filepath)

    except Exception as e:
        logging.error(f"Failed to process {original_filename}: {e}")
        os.makedirs(ERROR_DIR, exist_ok=True)
        shutil.move(filepath, os.path.join(ERROR_DIR, original_filename))

def main():
    init_database()
    while True:
        logging.info("Librarian is checking for files to convert...")
        all_files = [os.path.join(dp, f) for dp,_,fns in os.walk(INBOX_DIR) for f in fns if any(f.lower().endswith(ext) for ext in VALID_EXTENSIONS)]
        
        if all_files:
            batch_to_process = all_files[:BATCH_SIZE]
            logging.info(f"Found {len(all_files)} files to convert. Processing batch of {len(batch_to_process)}.")
            with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                executor.map(process_new_book, batch_to_process)
            logging.info("Batch finished. Checking for more...")
        else:
            logging.info("No new files to convert. Waiting...")
            time.sleep(60)

if __name__ == "__main__":
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
sudo bash -c "cat << EOF > /etc/systemd/system/librarian.service
[Unit]
Description=Librarian (Converter) Service
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 librarian.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting Librarian service..."
# This now correctly targets the main /factory directory
sudo chown -R $USER:$USER /factory
sudo systemctl daemon-reload
sudo systemctl start librarian
sudo systemctl enable librarian

echo "--- Librarian Setup Complete ---"
echo "To check the status, run: sudo systemctl status librarian"
echo "To watch the logs, run: tail -f /factory/logs/librarian.log"
