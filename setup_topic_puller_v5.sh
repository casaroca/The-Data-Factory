#!/bin/bash
set -e

echo "--- Setting up Topic Puller v2 (with PDF Salvage) v5 ---"

# --- 1. Define Paths ---
PROJECT_DIR="/factory/workers/extractors/topic_puller_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/topic_puller.log"
DB_PATH="/factory/db/library.db"
DB_DIR="$(dirname $DB_PATH)"
DISCARD_BIN="/factory/library/discarded"
SALVAGED_OUTPUT_DIR="/factory/data/raw/salvaged_from_discard"
UNSALVAGEABLE_DIR="/factory/library/discarded/unsalvageable_pdfs"
USER="tdf"

# --- 2. System Prerequisites ---
echo "[+] Installing prerequisites (poppler-utils for pdftotext)..."
sudo apt-get update
sudo apt-get install -y poppler-utils

# --- 3. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $SALVAGED_OUTPUT_DIR
mkdir -p $UNSALVAGEABLE_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE
mkdir -p $DB_DIR
mkdir -p $DISCARD_BIN

# --- 4. Create Application Files ---
echo "[+] Creating topic_puller.py application file..."
cp /home/tdf/topic_puller.py $PROJECT_DIR/topic_puller.py

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
cat << 'EOF' > $PROJECT_DIR/requirements.txt
# No external pip packages needed
EOF
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/topic_puller_v5.service
[Unit]
Description=Ebook Topic Puller Service v2 v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 topic_puller.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting Topic Puller v2 service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $SALVAGED_OUTPUT_DIR
sudo chown -R $USER:$USER $UNSALVAGEABLE_DIR
sudo chown $USER:$USER $LOG_FILE
sudo chown -R $USER:$USER $DB_DIR
sudo chown -R $USER:$USER $DISCARD_BIN
sudo systemctl daemon-reload
sudo systemctl start topic_puller_v5
sudo systemctl enable topic_puller_v5

echo "--- Topic Puller v2 Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status topic_puller_v5"
echo "To watch the logs, run: tail -f /factory/logs/topic_puller.log"