#!/bin/bash
set -e

echo "--- Setting up Factory-Wide Image Processor v5 ---"

# --- 1. System Prerequisites ---
echo "[+] Installing prerequisites (Poppler for PDFs, Unzip for EPUBs)..."
sudo apt-get update
sudo apt-get install -y python3-pip python3-venv poppler-utils unzip

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/processors/image_processor_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/image_processor.log"
DB_PATH="/factory/db/image_processing_log.db"
DB_DIR="$(dirname $DB_PATH)"
OUTPUT_DIR="/factory/data/final/image_datasets"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $OUTPUT_DIR
mkdir -p $DB_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE

# --- 4. Create Application Files ---
echo "[+] Creating Image Processor application files..."
cp /home/tdf/image_processor.py $PROJECT_DIR/image_processor.py

# --- 5. Create requirements.txt file ---
echo "[+] Creating requirements.txt file..."
cat << 'EOF' > $PROJECT_DIR/requirements.txt
Pillow
torch
transformers
EOF

# --- 6. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 7. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/image_processor_v5.service
[Unit]
Description=Factory-Wide Image Processor Service v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 image_processor.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 8. Start the Service ---
echo "[+] Starting Image Processor service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $OUTPUT_DIR
sudo chown -R $USER:$USER $DB_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start image_processor_v5
sudo systemctl enable image_processor_v5

echo "--- Image Processor Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status image_processor_v5"
echo "To watch the logs, run: tail -f /factory/logs/image_processor.log"
