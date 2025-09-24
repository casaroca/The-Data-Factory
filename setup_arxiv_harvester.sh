#!/bin/bash
set -e

echo "--- Setting up arXiv Harvester (Fixed) ---"

# --- 1. Stop and remove the old service ---
echo "[+] Stopping and removing old arxiv_harvester service..."
sudo systemctl stop arxiv_harvester || true
sudo systemctl disable arxiv_harvester || true
sudo rm -f /etc/systemd/system/arxiv_harvester.service
sudo rm -rf /factory/workers/collectors/arxiv_harvester
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/arxiv_harvester"
LOG_DIR="/factory/logs"
RAW_DUMP_DIR="/factory/data/raw/arxiv_papers"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $RAW_DUMP_DIR

# --- 4. Create Application Files ---
echo "[+] Creating arxiv_harvester.py application file..."
cat << 'EOF' > $PROJECT_DIR/arxiv_harvester.py
import os
import time
import logging
import arxiv
import random
from concurrent.futures import ThreadPoolExecutor
import tarfile
import tempfile
import shutil

# --- Configuration ---
LOG_DIR = "/factory/logs"
RAW_DUMP_DIR = "/factory/data/raw/arxiv_papers"
MAX_WORKERS = 10
REST_PERIOD_SECONDS = 60 # 1 minute rest period

# High-value queries from your list
SEARCH_QUERIES = [
    "philosophy", "logic AND reasoning", "critical thinking", "epistemology", "metaphysics",
    "ethics", "history of science", "linguistics", "sociology", "anthropology",
    "political science", "economics", "psychology", "education theory", "international relations",
    "physics", "chemistry", "biology", "astronomy", "mathematics",
    "computer science", "artificial intelligence", "machine learning", "data structures",
    "electronics", "information theory", "pathology", "pharmacology", "epidemiology",
    "public health", "nutrition science", "art history", "music theory", "architecture history",
    "design principles", "aesthetics philosophy", "cultural studies", "mathematical logic",
    "problem solving techniques"
]

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'arxiv_harvester.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def process_paper(paper):
    """Downloads the source of a paper, extracts text, and saves it."""
    temp_dir = None
    try:
        logging.info(f"Processing paper: {paper.title}")
        
        # Create a unique filename
        sanitized_title = "".join([c for c in paper.title if c.isalnum() or c in (' ', '-')]).rstrip()
        output_filename = f"arxiv_{sanitized_title}.txt"
        output_path = os.path.join(RAW_DUMP_DIR, output_filename)

        full_text = ""
        source_available = True
        
        try:
            # Create a temporary directory for this paper
            temp_dir = tempfile.mkdtemp()
            
            # Download the source to the temporary directory
            downloaded_path = paper.download_source(dirpath=temp_dir)
            
            # Try to open as tar.gz first
            try:
                with tarfile.open(downloaded_path, mode="r:gz") as tar:
                    for member in tar.getmembers():
                        # Extract only .tex (LaTeX) files, which are pure text
                        if member.isfile() and member.name.endswith('.tex'):
                            extracted_file = tar.extractfile(member)
                            if extracted_file:
                                full_text += extracted_file.read().decode('utf-8', errors='ignore') + "\n\n"
            except (tarfile.ReadError, OSError, IOError):
                # If it's not a valid tar.gz file, try to read as plain text
                try:
                    with open(downloaded_path, 'r', encoding='utf-8', errors='ignore') as f:
                        content = f.read()
                        if content.strip():
                            full_text = content
                except Exception:
                    # If that fails too, try as binary and decode
                    try:
                        with open(downloaded_path, 'rb') as f:
                            content = f.read().decode('utf-8', errors='ignore')
                            if content.strip():
                                full_text = content
                    except Exception:
                        source_available = False
                        
        except Exception as download_error:
            logging.warning(f"Could not download source for {paper.title}: {download_error}")
            source_available = False
        
        # Save the paper data
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(f"Title: {paper.title}\n")
            f.write(f"Authors: {', '.join([str(author) for author in paper.authors])}\n")
            f.write(f"Published: {paper.published}\n")
            f.write(f"arXiv ID: {paper.entry_id}\n")
            f.write(f"Abstract: {paper.summary}\n")
            f.write("="*80 + "\n")
            
            if full_text and full_text.strip():
                f.write("FULL TEXT:\n")
                f.write("="*80 + "\n")
                f.write(full_text)
                logging.info(f"Successfully extracted and saved text to {output_path}")
            else:
                f.write("METADATA ONLY:\n")
                f.write("="*80 + "\n")
                f.write("[Note: Source files not available or could not be processed - saved abstract and metadata]\n")
                logging.info(f"Source not available, saved metadata and abstract to {output_path}")

    except Exception as e:
        logging.error(f"Failed to process paper {paper.title}: {e}")
    finally:
        # Clean up temporary directory
        if temp_dir and os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)

def main():
    while True:
        logging.info("--- Starting new arXiv Harvester cycle ---")
        
        try:
            query = random.choice(SEARCH_QUERIES)
            logging.info(f"Querying arXiv API for: '{query}'")
            
            # Search for the 20 most relevant recent papers for the query
            search = arxiv.Search(
                query=query,
                max_results=20,
                sort_by=arxiv.SortCriterion.Relevance,
                sort_order=arxiv.SortOrder.Descending
            )
            
            results = list(search.results())
            logging.info(f"API returned {len(results)} results for query.")

            if results:
                with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
                    executor.map(process_paper, results)

        except Exception as e:
            logging.error(f"An error occurred during the API search: {e}")

        logging.info(f"--- Cycle finished. Waiting {REST_PERIOD_SECONDS} seconds... ---")
        time.sleep(REST_PERIOD_SECONDS)

if __name__ == "__main__":
    main()
EOF

cat << 'EOF' > $PROJECT_DIR/requirements.txt
arxiv
requests
beautifulsoup4
EOF

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/arxiv_harvester.service
[Unit]
Description=arXiv Harvester Service
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 arxiv_harvester.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting arXiv Harvester service..."
sudo chown -R $USER:$USER /factory
sudo systemctl daemon-reload
sudo systemctl start arxiv_harvester
sudo systemctl enable arxiv_harvester

echo "--- arXiv Harvester Setup Complete ---"
echo "To check the status, run: sudo systemctl status arxiv_harvester"
echo "To watch the logs, run: tail -f /factory/logs/arxiv_harvester.log"
