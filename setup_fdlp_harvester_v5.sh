#!/bin/bash
set -e

echo "--- Setting up FDLP Harvester v1 (Final Working Version) v5 ---"

# --- 1. Stop and remove all old versions to prevent conflicts ---
echo "[+] Stopping and removing all old fdlp_harvester services..."
sudo systemctl stop fdlp_harvester fdlp_harvester2 || true
sudo systemctl disable fdlp_harvester fdlp_harvester2 || true
sudo rm -f /etc/systemd/system/fdlp_harvester*.service
sudo rm -rf /factory/workers/collectors/fdlp_harvester
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/fdlp_harvester_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/fdlp_harvester.log"
DB_PATH="/factory/db/fdlp_log.db"
DB_DIR="$(dirname $DB_PATH)"
BOOK_DEPOSIT_DIR="/factory/library/book_deposit"
USER="tdf"

# --- 3. System Prerequisites ---
echo "[+] Installing prerequisites..."
sudo apt-get update
sudo apt-get install -y python3-pip python3-venv

# --- 4. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $BOOK_DEPOSIT_DIR
mkdir -p $DB_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE

# --- 5. Create Application Files ---
echo "[+] Creating fdlp_harvester.py application file..."
cp /home/tdf/fdlp_harvester.py $PROJECT_DIR/fdlp_harvester.py

# --- 6. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install internetarchive

# --- 7. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/fdlp_harvester_v5.service
[Unit]
Description=FDLP Harvester Service v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 fdlp_harvester.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 8. Start the Service ---
echo "[+] Starting FDLP Harvester service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $BOOK_DEPOSIT_DIR
sudo chown -R $USER:$USER $DB_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start fdlp_harvester_v5
sudo systemctl enable fdlp_harvester_v5

echo "--- FDLP Harvester Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status fdlp_harvester_v5"
echo "To watch the logs, run: tail -f /factory/logs/fdlp_harvester.log"
