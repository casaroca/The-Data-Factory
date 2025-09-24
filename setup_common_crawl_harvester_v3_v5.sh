#!/bin/bash
set -e

echo "--- Setting up Common Crawl Harvester v3 (DB Fix) v5 ---"

# --- 1. Stop and remove all old versions to prevent conflicts ---
echo "[+] Stopping and removing all old common_crawl collector services..."
sudo systemctl stop common_crawl_harvester common_crawl_harvester_v2 || true
sudo systemctl disable common_crawl_harvester common_crawl_harvester_v2 || true
sudo rm -f /etc/systemd/system/common_crawl_harvester*.service
sudo rm -rf /factory/workers/collectors/common_crawl_harvester*
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/common_crawl_harvester_v3_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/common_crawl_harvester_v3.log"
DB_DIR="/factory/db"
DB_PATH="$DB_DIR/common_crawl_log.db"
RAW_DUMP_DIR="/factory/data/raw/common_crawl_harvest"
USER="tdf"

# --- 3. THE FIX: Remove the old, incorrect database file ---
echo "[+] Removing old database file to ensure a clean schema..."
sudo rm -f $DB_PATH

# --- 4. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $RAW_DUMP_DIR
mkdir -p $DB_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE

# --- 5. Create Application Files ---
echo "[+] Creating common_crawl_harvester_v3.py application file..."
cp /home/tdf/common_crawl_harvester_v3.py $PROJECT_DIR/common_crawl_harvester_v3.py

# --- 6. Create requirements.txt file ---
echo "[+] Creating requirements.txt file..."
cat << 'EOF' > $PROJECT_DIR/requirements.txt
requests
beautifulsoup4
warcio
lxml
EOF

# --- 7. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 8. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/common_crawl_harvester_v3_v5.service
[Unit]
Description=Common Crawl Harvester Service v3 v5
After=network.target

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
Environment=PYTHONUNBUFFERED=1
ExecStart=$PROJECT_DIR/venv/bin/python3 common_crawl_harvester_v3.py
Restart=on-failure
RestartSec=300
TimeoutStopSec=60
KillMode=mixed
LimitNOFILE=65536
MemoryMax=4G

[Install]
WantedBy=multi-user.target
EOF"

# --- 9. Start the Service ---
echo "[+] Starting Common Crawl Harvester v3 service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $RAW_DUMP_DIR
sudo chown -R $USER:$USER $DB_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start common_crawl_harvester_v3_v5
sudo systemctl enable common_crawl_harvester_v3_v5

echo "--- Common Crawl Harvester v3 Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status common_crawl_harvester_v3_v5"
echo "To watch the logs, run: tail -f /factory/logs/common_crawl_harvester_v3.log"
