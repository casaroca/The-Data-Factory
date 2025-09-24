#!/bin/bash
set -e

echo "--- Setting up Public Dataset Harvester v2 v5 ---"

# --- 1. Stop and remove the old service to prevent conflicts ---
echo "[+] Stopping and removing old public_dataset_harvester service..."
sudo systemctl stop public_dataset_harvester || true
sudo systemctl disable public_dataset_harvester || true
sudo rm -f /etc/systemd/system/public_dataset_harvester.service
sudo rm -rf /factory/workers/collectors/public_dataset_harvester
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/public_dataset_harvester_v2_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/public_dataset_harvester_v2.log"
DB_PATH="/factory/db/public_dataset_log.db"
DB_DIR="$(dirname $DB_PATH)"
RAW_DUMP_DIR="/factory/data/raw/huggingface_datasets"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $RAW_DUMP_DIR
mkdir -p $DB_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE

# --- 4. Create Application Files ---
echo "[+] Creating public_dataset_harvester_v2.py application file..."
cp /home/tdf/public_dataset_harvester_v2.py $PROJECT_DIR/public_dataset_harvester_v2.py

# --- 5. Create requirements.txt file ---
echo "[+] Creating requirements.txt file..."
cat << 'EOF' > $PROJECT_DIR/requirements.txt
datasets
EOF

# --- 6. Set Up Python Environment ---
echo "[+] Setting up Python environment (this may take a moment)..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 7. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/public_dataset_harvester_v2_v5.service
[Unit]
Description=Public Dataset Harvester Service v2 v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 public_dataset_harvester_v2.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 8. Start the Service ---
echo "[+] Starting Public Dataset Harvester v2 service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $RAW_DUMP_DIR
sudo chown -R $USER:$USER $DB_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start public_dataset_harvester_v2_v5
sudo systemctl enable public_dataset_harvester_v2_v5

echo "--- Public Dataset Harvester v2 Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status public_dataset_harvester_v2_v5"
echo "To watch the logs, run: tail -f /factory/logs/public_dataset_harvester_v2.log"
