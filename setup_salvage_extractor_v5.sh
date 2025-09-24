#!/bin/bash
set -e

echo "--- Setting up Salvage Extractor v2 (Factory-Wide) v5 ---"

# --- 1. Stop and remove the old service ---
echo "[+] Stopping and removing old salvage_extractor service..."
sudo systemctl stop salvage_extractor || true
sudo systemctl disable salvage_extractor || true
sudo rm -f /etc/systemd/system/salvage_extractor.service
sudo rm -rf /factory/workers/processors/salvage_extractor
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/processors/salvage_extractor_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/salvage_extractor.log"
DB_PATH="/factory/db/salvage_log.db"
DB_DIR="$(dirname $DB_PATH)"
RAW_DUMP_DIR="/factory/data/raw/salvaged_text"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $RAW_DUMP_DIR
mkdir -p $DB_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE

# --- 4. Create Application Files ---
echo "[+] Creating Salvage Extractor v2 application files..."
cp /home/tdf/salvage_extractor.py $PROJECT_DIR/salvage_extractor.py

# --- 5. Create requirements.txt file ---
echo "[+] Creating requirements.txt file..."
cat << 'EOF' > $PROJECT_DIR/requirements.txt
Pillow
EOF

# --- 6. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 7. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/salvage_extractor_v5.service
[Unit]
Description=Salvage Extractor Service v2 (Factory-Wide) v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 salvage_extractor.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 8. Start the Service ---
echo "[+] Starting Salvage Extractor v2 service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $RAW_DUMP_DIR
sudo chown -R $USER:$USER $DB_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start salvage_extractor_v5
sudo systemctl enable salvage_extractor_v5

echo "--- Salvage Extractor v2 Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status salvage_extractor_v5"
echo "To watch the logs, run: tail -f /factory/logs/salvage_extractor.log"
