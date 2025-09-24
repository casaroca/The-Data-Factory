#!/bin/bash
set -e

echo "--- Setting up Enhanced Consolidated Librarian (High-Performance) ---"

# --- 1. Stop and remove the old librarian services ---
echo "[+] Stopping and removing old librarian and jr_librarian services..."
sudo systemctl stop librarian || true
sudo systemctl disable librarian || true
sudo systemctl stop jr_librarian || true
sudo systemctl disable jr_librarian || true
sudo rm -f /etc/systemd/system/librarian.service
sudo rm -f /etc/systemd/system/jr_librarian.service
sudo rm -rf /factory/workers/organizers/librarian
sudo rm -rf /factory/workers/organizers/jr_librarian
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/organizers/librarian"
LOG_DIR="/factory/logs"
DB_PATH="/factory/db/library.db"
INBOX_DIR="/factory/library/book_deposit"
LIBRARY_DIR="/factory/library/library"
ERROR_DIR="/factory/library/discarded"
MEDIA_DIR="/factory/library/media_for_processing"
RAW_DATA_DIR="/factory/data/raw/from_library"
USER="tdf"
# --- FIX: Define top-level directories for chown command ---
FACTORY_HOME="/factory"
LIBRARY_HOME="/library"

# --- 3. Create Directories ---
echo "[+] Creating project directories..."
mkdir -p $PROJECT_DIR
mkdir -p $MEDIA_DIR
mkdir -p $RAW_DATA_DIR

# --- 4. Create Application Files ---
echo "[+] Creating new Enhanced Librarian application files..."
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
import mimetypes

# --- Configuration ---
LOG_DIR = "/factory/logs"
DB_PATH = "/factory/db/library.db"
INBOX_DIR = "/factory/library/book_deposit"
LIBRARY_DIR = "/factory/library/library"
ERROR_DIR = "/factory/library/discarded"
MEDIA_DIR = "/factory/library/media_for_processing"
RAW_DATA_DIR = "/factory/data/raw/from_library"
MAX_WORKERS = 15
BATCH_SIZE = 30
CONVERSION_EXTENSIONS = ['.txt', '.pdf', '.mobi', '.html', '.docx', '.rtf', '.odt', '.doc']
EPUB_EXTENSION = '.epub'
MEDIA_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.gif', '.mp3', '.wav', '.mp4', '.mov', '.avi', '.mkv']

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'librarian.log'), level=logging.INFO, 
                   format='%(asctime)s - %(levelname)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def init_database():
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        c.execute('''
            CREATE TABLE IF NOT EXISTS books (
                id INTEGER PRIMARY KEY, title TEXT, author TEXT, category TEXT,
                filepath TEXT UNIQUE, added_date TEXT
            )''')
        c.execute('''
            CREATE TABLE IF NOT EXISTS raw_data (
                id INTEGER PRIMARY KEY, original_filename TEXT, converted_filename TEXT,
                file_type TEXT, filepath TEXT UNIQUE, added_date TEXT
            )''')
        conn.commit()

def convert_to_epub(input_path):
    """Attempts to convert file to EPUB using Calibre."""
    output_filename = os.path.splitext(os.path.basename(input_path))[0] + ".epub"
    temp_output_path = os.path.join("/tmp", output_filename)
    cmd = ['/opt/calibre/ebook-convert', input_path, temp_output_path, '--enable-heuristics']
    result = subprocess.run(cmd, capture_output=True, text=True, errors='ignore', timeout=900)
    if result.returncode != 0:
        raise Exception(f"Calibre conversion failed: {result.stderr}")
    return temp_output_path

def convert_to_text(input_path):
    """Converts various file types to plain text for archival."""
    original_filename = os.path.basename(input_path)
    text_filename = os.path.splitext(original_filename)[0] + ".txt"
    temp_output_path = os.path.join("/tmp", text_filename)
    
    file_ext = os.path.splitext(input_path)[1].lower()
    
    try:
        if file_ext == '.pdf':
            # Use pdftotext for PDF files
            cmd = ['pdftotext', input_path, temp_output_path]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            if result.returncode != 0:
                raise Exception(f"PDF text extraction failed: {result.stderr}")
        
        elif file_ext in ['.docx', '.doc', '.odt']:
            # Use LibreOffice for document files
            cmd = ['libreoffice', '--headless', '--convert-to', 'txt:Text', '--outdir', '/tmp', input_path]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            if result.returncode != 0:
                raise Exception(f"LibreOffice conversion failed: {result.stderr}")
        
        elif file_ext in ['.html', '.htm']:
            # Use lynx or w3m for HTML files
            cmd = ['lynx', '-dump', '-nolist', input_path]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            if result.returncode != 0:
                # Fallback to w3m
                cmd = ['w3m', '-dump', input_path]
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
                if result.returncode != 0:
                    raise Exception("HTML text extraction failed")
            with open(temp_output_path, 'w', encoding='utf-8') as f:
                f.write(result.stdout)
        
        elif file_ext == '.txt':
            # Just copy text files
            shutil.copy2(input_path, temp_output_path)
        
        elif file_ext in ['.rtf']:
            # Use unrtf for RTF files
            cmd = ['unrtf', '--text', input_path]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            if result.returncode != 0:
                raise Exception(f"RTF text extraction failed: {result.stderr}")
            with open(temp_output_path, 'w', encoding='utf-8') as f:
                f.write(result.stdout)
        
        else:
            raise Exception(f"Unsupported file type for text conversion: {file_ext}")
        
        if not os.path.exists(temp_output_path) or os.path.getsize(temp_output_path) == 0:
            raise Exception("Text conversion produced empty or missing file")
        
        return temp_output_path
    
    except Exception as e:
        if os.path.exists(temp_output_path):
            os.remove(temp_output_path)
        raise e

def get_metadata(epub_path):
    """Extract metadata from EPUB files."""
    cmd = ['/opt/calibre/ebook-meta', epub_path]
    result = subprocess.run(cmd, capture_output=True, text=True, errors='ignore')
    if result.returncode != 0:
        return {'title': os.path.splitext(os.path.basename(epub_path))[0]}
    return {k.strip().lower(): v.strip() for k, v in (line.split(":", 1) for line in result.stdout.splitlines() if ":" in line)}

def categorize_book(metadata):
    """Categorize books based on metadata."""
    tags = metadata.get('tags', '').lower()
    title = metadata.get('title', '').lower()
    
    if any(g in tags for g in ['fiction', 'novel', 'story']):
        return "Fiction"
    elif any(g in tags for g in ['science', 'tech', 'computer', 'programming']):
        return "Technical"
    elif any(g in tags for g in ['history', 'biography', 'memoir']):
        return "Non-Fiction"
    elif any(g in title for g in ['manual', 'guide', 'reference']):
        return "Reference"
    return "Unsorted"

def categorize_raw_data(filename, file_ext):
    """Categorize raw data files for organization."""
    filename_lower = filename.lower()
    
    if any(term in filename_lower for term in ['manual', 'guide', 'documentation', 'readme']):
        return "Documentation"
    elif any(term in filename_lower for term in ['report', 'analysis', 'study']):
        return "Reports"
    elif any(term in filename_lower for term in ['article', 'paper', 'journal']):
        return "Articles"
    elif file_ext in ['.pdf']:
        return "PDFs"
    elif file_ext in ['.docx', '.doc', '.odt']:
        return "Documents"
    elif file_ext in ['.html', '.htm']:
        return "Web_Content"
    else:
        return "Miscellaneous"

def process_file(filepath):
    """Intelligently processes a file based on its type."""
    original_filename = os.path.basename(filepath)
    file_ext = os.path.splitext(filepath)[1].lower()
    
    try:
        # First, try to convert to EPUB
        if filepath.lower().endswith(EPUB_EXTENSION):
            epub_path = filepath
            logging.info(f"Filing EPUB: {original_filename}")
        else:
            try:
                logging.info(f"Attempting EPUB conversion: {original_filename}")
                epub_path = convert_to_epub(filepath)
                logging.info(f"Successfully converted to EPUB: {original_filename}")
            except Exception as epub_error:
                logging.warning(f"EPUB conversion failed for {original_filename}: {epub_error}")
                logging.info(f"Attempting text conversion for archival: {original_filename}")
                
                try:
                    # Convert to text for archival
                    text_path = convert_to_text(filepath)
                    
                    # Organize in raw data directory
                    category = categorize_raw_data(original_filename, file_ext)
                    category_dir = os.path.join(RAW_DATA_DIR, category)
                    os.makedirs(category_dir, exist_ok=True)
                    
                    text_filename = os.path.basename(text_path)
                    final_text_path = os.path.join(category_dir, text_filename)
                    
                    # Move to final location
                    shutil.move(text_path, final_text_path)
                    
                    # Record in database
                    with sqlite3.connect(DB_PATH) as conn:
                        c = conn.cursor()
                        c.execute('''INSERT OR IGNORE INTO raw_data 
                                   (original_filename, converted_filename, file_type, filepath, added_date) 
                                   VALUES (?,?,?,?,?)''',
                                 (original_filename, text_filename, file_ext, final_text_path, datetime.now().isoformat()))
                        conn.commit()
                    
                    logging.info(f"Successfully archived as text: {original_filename} -> {category}/{text_filename}")
                    
                    # Remove original file
                    os.remove(filepath)
                    return
                    
                except Exception as text_error:
                    logging.error(f"Both EPUB and text conversion failed for {original_filename}: {text_error}")
                    # Move to error directory
                    os.makedirs(ERROR_DIR, exist_ok=True)
                    shutil.move(filepath, os.path.join(ERROR_DIR, original_filename))
                    return
        
        # Process as EPUB (either original or converted)
        metadata = get_metadata(epub_path)
        category = categorize_book(metadata)
        category_dir = os.path.join(LIBRARY_DIR, category)
        os.makedirs(category_dir, exist_ok=True)
        
        final_epub_filename = os.path.basename(epub_path)
        final_path = os.path.join(category_dir, final_epub_filename)
        
        # Handle filename conflicts
        counter = 1
        while os.path.exists(final_path):
            name, ext = os.path.splitext(final_epub_filename)
            final_epub_filename = f"{name}_{counter}{ext}"
            final_path = os.path.join(category_dir, final_epub_filename)
            counter += 1
        
        shutil.move(epub_path, final_path)
        
        # Record in database
        with sqlite3.connect(DB_PATH) as conn:
            c = conn.cursor()
            c.execute('''INSERT OR IGNORE INTO books (title, author, category, filepath, added_date) 
                        VALUES (?,?,?,?,?)''',
                      (metadata.get('title', 'Unknown'), metadata.get('author(s)', 'Unknown'), 
                       category, final_path, datetime.now().isoformat()))
            conn.commit()
        
        logging.info(f"Successfully registered EPUB: '{metadata.get('title')}'")
        
        # Remove original file if it was converted
        if filepath != epub_path and os.path.exists(filepath):
            os.remove(filepath)
            
    except Exception as e:
        logging.error(f"Failed to process {original_filename}: {e}")
        if os.path.exists(filepath):
            os.makedirs(ERROR_DIR, exist_ok=True)
            shutil.move(filepath, os.path.join(ERROR_DIR, original_filename))

def move_media_and_cleanup():
    """Finds media files and cleans up empty directories."""
    logging.info("Scanning for media files and cleaning up empty directories...")
    for dirpath, dirnames, filenames in os.walk(INBOX_DIR, topdown=False):
        for filename in filenames:
            if any(filename.lower().endswith(ext) for ext in MEDIA_EXTENSIONS):
                filepath = os.path.join(dirpath, filename)
                try:
                    os.makedirs(MEDIA_DIR, exist_ok=True)
                    shutil.move(filepath, os.path.join(MEDIA_DIR, filename))
                    logging.info(f"Moved media file: {filename}")
                except Exception as e:
                    logging.error(f"Could not move media file {filename}: {e}")
        
        # Remove empty directories
        if not os.listdir(dirpath) and os.path.realpath(dirpath) != os.path.realpath(INBOX_DIR):
            try:
                os.rmdir(dirpath)
                logging.info(f"Removed empty directory: {dirpath}")
            except OSError: 
                pass

def get_processing_stats():
    """Get statistics about processed files."""
    try:
        with sqlite3.connect(DB_PATH) as conn:
            c = conn.cursor()
            c.execute('SELECT COUNT(*) FROM books')
            epub_count = c.fetchone()[0]
            c.execute('SELECT COUNT(*) FROM raw_data')
            raw_data_count = c.fetchone()[0]
            return epub_count, raw_data_count
    except:
        return 0, 0

def main():
    init_database()
    epub_count, raw_data_count = get_processing_stats()
    logging.info(f"Librarian starting - Current library: {epub_count} EPUBs, {raw_data_count} raw data files")
    
    while True:
        logging.info("Librarian is checking for new files...")
        
        # Find all processable files
        all_files = []
        for dp, _, fns in os.walk(INBOX_DIR):
            for f in fns:
                full_path = os.path.join(dp, f)
                if any(f.lower().endswith(ext) for ext in CONVERSION_EXTENSIONS + [EPUB_EXTENSION]):
                    all_files.append(full_path)
        
        if all_files:
            # Process EPUBs first (faster)
            epubs_to_process = [f for f in all_files if f.lower().endswith(EPUB_EXTENSION)]
            files_to_convert = [f for f in all_files if not f.lower().endswith(EPUB_EXTENSION)]
            
            for file_list in [epubs_to_process, files_to_convert]:
                if file_list:
                    batch = file_list[:BATCH_SIZE]
                    task_type = 'EPUBs' if file_list == epubs_to_process else 'files for conversion'
                    logging.info(f"Processing a batch of {len(batch)} {task_type}.")
                    
                    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                        executor.map(process_file, batch)
            
            logging.info("Batch finished. Running cleanup and checking for more...")
            move_media_and_cleanup()
            
            # Log updated stats
            new_epub_count, new_raw_data_count = get_processing_stats()
            if new_epub_count > epub_count or new_raw_data_count > raw_data_count:
                logging.info(f"Library updated - EPUBs: {new_epub_count} (+{new_epub_count - epub_count}), "
                           f"Raw data: {new_raw_data_count} (+{new_raw_data_count - raw_data_count})")
                epub_count, raw_data_count = new_epub_count, new_raw_data_count
        else:
            logging.info("No new files found. Waiting...")
            time.sleep(60)

if __name__ == "__main__":
    main()
EOF

cat << 'EOF' > $PROJECT_DIR/requirements.txt
# No external pip packages needed - using system tools
EOF

# --- 5. Install Required System Tools ---
echo "[+] Installing required system tools for text conversion..."
sudo apt-get update
sudo apt-get install -y poppler-utils libreoffice lynx w3m unrtf

# --- 6. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 7. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/librarian.service
[Unit]
Description=Enhanced Librarian (Consolidated) Service
After=network-online.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 librarian.py
Restart=always
RestartSec=10
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF"

# --- 8. Create Raw Data Monitoring Script ---
echo "[+] Creating raw data monitoring script..."
cat << 'EOF' > $PROJECT_DIR/monitor_raw_data.py
#!/usr/bin/env python3
import sqlite3
import os
from datetime import datetime

DB_PATH = "/factory/db/library.db"
RAW_DATA_DIR = "/factory/library/raw_data"

def show_raw_data_stats():
    """Display statistics about raw data files."""
    try:
        with sqlite3.connect(DB_PATH) as conn:
            c = conn.cursor()
            
            print("=== RAW DATA ARCHIVE STATISTICS ===")
            print(f"Report generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
            print()
            
            # Total count
            c.execute('SELECT COUNT(*) FROM raw_data')
            total_count = c.fetchone()[0]
            print(f"Total archived files: {total_count}")
            print()
            
            # By file type
            c.execute('SELECT file_type, COUNT(*) FROM raw_data GROUP BY file_type ORDER BY COUNT(*) DESC')
            file_type_stats = c.fetchall()
            if file_type_stats:
                print("By file type:")
                for file_type, count in file_type_stats:
                    print(f"  {file_type}: {count}")
                print()
            
            # Recent additions
            c.execute('SELECT original_filename, file_type, added_date FROM raw_data ORDER BY added_date DESC LIMIT 10')
            recent_files = c.fetchall()
            if recent_files:
                print("Recent additions:")
                for filename, file_type, added_date in recent_files:
                    print(f"  {added_date[:19]} - {filename} ({file_type})")
                print()
            
            # Directory structure
            if os.path.exists(RAW_DATA_DIR):
                print("Raw data directory structure:")
                for category in sorted(os.listdir(RAW_DATA_DIR)):
                    category_path = os.path.join(RAW_DATA_DIR, category)
                    if os.path.isdir(category_path):
                        file_count = len([f for f in os.listdir(category_path) if os.path.isfile(os.path.join(category_path, f))])
                        print(f"  {category}/: {file_count} files")
            
    except Exception as e:
        print(f"Error generating stats: {e}")

if __name__ == "__main__":
    show_raw_data_stats()
EOF

chmod +x $PROJECT_DIR/monitor_raw_data.py

# --- 9. Start the Service ---
echo "[+] Starting enhanced Librarian service..."
# --- FIX: Target only the top-level directories to avoid race conditions ---
sudo chown -R $USER:$USER $FACTORY_HOME $LIBRARY_HOME
sudo systemctl daemon-reload
sudo systemctl start librarian
sudo systemctl enable librarian

echo "--- Enhanced Consolidated Librarian Setup Complete ---"
echo ""
echo "New Features:"
echo "- Files that can't convert to EPUB are converted to text and archived in $RAW_DATA_DIR"
echo "- Raw data is automatically categorized (Documentation, Reports, Articles, etc.)"
echo "- Enhanced logging with processing statistics"
echo "- Support for additional file formats (RTF, ODT, etc.)"
echo ""
echo "Directory Structure:"
echo "- EPUBs: $LIBRARY_DIR"
echo "- Raw Data: $RAW_DATA_DIR"
echo "- Media: $MEDIA_DIR"
echo "- Errors: $ERROR_DIR"
echo ""
echo "Commands:"
echo "- Check status: sudo systemctl status librarian"
echo "- Watch logs: tail -f /factory/logs/librarian.log"
echo "- Raw data stats: $PROJECT_DIR/monitor_raw_data.py"
