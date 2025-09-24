#!/bin/bash
set -e

echo "--- Setting up Data Packager (Corrected) ---"

# --- 1. Define Paths ---
PROJECT_DIR="/factory/workers/processors/data_packager"
LOG_DIR="/factory/logs"
FINAL_DATA_DIR="/factory/data/final"
PACKAGE_OUTPUT_DIR="/factory/data/final/packages"
USER="tdf"

# --- 2. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $PACKAGE_OUTPUT_DIR

# --- 3. Create Application Files ---
echo "[+] Creating data_packager.py application file..."
cat << 'EOF' > $PROJECT_DIR/data_packager.py
import os
import time
import logging
import shutil
import tarfile
from datetime import datetime

# --- Configuration ---
LOG_DIR = "/factory/logs"
FINAL_DATA_DIR = "/factory/data/final"
PACKAGE_OUTPUT_DIR = "/factory/data/final/packages"
THRESHOLD_GB = 10
THRESHOLD_BYTES = THRESHOLD_GB * 1024 * 1024 * 1024

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(
    filename=os.path.join(LOG_DIR, 'data_packager.log'),
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logging.getLogger('').addHandler(logging.StreamHandler())

def get_domain_from_filename(filename):
    """Extracts the domain name from a dataset filename."""
    # Example: prompts_business_news.csv -> business_news
    parts = os.path.splitext(filename)[0].split('_', 1)
    if len(parts) > 1:
        return parts[1]
    return None

def package_domain_datasets(domain):
    """Finds all 4 dataset files for a domain and packages them."""
    logging.info(f"Packaging all datasets for domain: {domain}...")
    
    source_dirs = {
        "instructions_jsonl": os.path.join(FINAL_DATA_DIR, "instructions/jsonl"),
        "instructions_csv": os.path.join(FINAL_DATA_DIR, "instructions/csv"),
        "prompts_jsonl": os.path.join(FINAL_DATA_DIR, "prompts/jsonl"),
        "prompts_csv": os.path.join(FINAL_DATA_DIR, "prompts/csv")
    }

    files_to_package = {
        "instructions.jsonl": os.path.join(source_dirs["instructions_jsonl"], f"instructions_{domain}.jsonl"),
        "instructions.csv": os.path.join(source_dirs["instructions_csv"], f"instructions_{domain}.csv"),
        "prompts.jsonl": os.path.join(source_dirs["prompts_jsonl"], f"prompts_{domain}.jsonl"),
        "prompts.csv": os.path.join(source_dirs["prompts_csv"], f"prompts_{domain}.csv")
    }

    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    archive_name = f"{domain}_dataset_{timestamp}.tar.gz"
    archive_path = os.path.join(PACKAGE_OUTPUT_DIR, archive_name)

    try:
        with tarfile.open(archive_path, "w:gz") as tar:
            for arcname, full_path in files_to_package.items():
                if os.path.exists(full_path):
                    tar.add(full_path, arcname=os.path.join(domain, arcname))
                    logging.info(f"  + Added {arcname} to archive.")
        
        logging.info(f"Successfully created package: {archive_path}")

        # After successful packaging, delete the original files
        for full_path in files_to_package.values():
            if os.path.exists(full_path):
                os.remove(full_path)
                logging.info(f"  - Removed original file: {os.path.basename(full_path)}")
        
        return True

    except Exception as e:
        logging.error(f"Failed to create package for domain {domain}: {e}")
        # Clean up failed archive attempt
        if os.path.exists(archive_path):
            os.remove(archive_path)
        return False

def main():
    while True:
        logging.info("--- Data Packager checking for large datasets... ---")
        packaged_domains = set()

        # Scan all final data directories
        for root, _, files in os.walk(FINAL_DATA_DIR):
            for filename in files:
                filepath = os.path.join(root, filename)
                domain = get_domain_from_filename(filename)

                if domain and domain not in packaged_domains:
                    try:
                        if os.path.getsize(filepath) > THRESHOLD_BYTES:
                            logging.info(f"Threshold reached for {filename} in domain '{domain}'. Triggering packaging.")
                            if package_domain_datasets(domain):
                                packaged_domains.add(domain) # Prevent re-packaging in the same cycle
                    except FileNotFoundError:
                        continue # File might have been moved by another thread
        
        if not packaged_domains:
            logging.info("No datasets have reached the size threshold. Waiting...")

        logging.info("--- Cycle finished. Waiting 15 minutes... ---")
        time.sleep(15 * 60)

if __name__ == "__main__":
    main()
EOF

cat << 'EOF' > $PROJECT_DIR/requirements.txt
# No external pip packages needed
EOF

# --- 4. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 5. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/data_packager.service
[Unit]
Description=Data Packager Service
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 data_packager.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 6. Start the Service ---
echo "[+] Setting permissions and starting Data Packager service..."
# THE FIX: This command now only targets the new directories, making it much faster.
sudo chown -R $USER:$USER $PROJECT_DIR $PACKAGE_OUTPUT_DIR
sudo systemctl daemon-reload
sudo systemctl start data_packager
sudo systemctl enable data_packager

echo "--- Data Packager Setup Complete ---"
echo "To check the status, run: sudo systemctl status data_packager"
echo "To watch the logs, run: tail -f /factory/logs/data_packager.log"

