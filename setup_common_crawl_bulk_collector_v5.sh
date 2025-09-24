#!/bin/bash
set -e

echo "--- Setting up Common Crawl Bulk Collector v5 ---"

# --- 1. Stop and remove all old versions to prevent conflicts ---
echo "[+] Stopping and removing all old common_crawl_collector services..."
sudo systemctl stop common_crawl_query_collector || true
sudo systemctl disable common_crawl_query_collector || true
sudo rm -f /etc/systemd/system/common_crawl_query_collector.service
sudo rm -rf /factory/workers/collectors/common_crawl_query_collector
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/common_crawl_bulk_collector_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/common_crawl_bulk_collector.log"
DB_PATH="/factory/db/common_crawl_log.db"
RAW_DUMP_DIR="/factory/data/raw/common_crawl_bulk"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $RAW_DUMP_DIR
mkdir -p $(dirname $DB_PATH)
mkdir -p $LOG_DIR
touch $LOG_FILE

# --- 4. Create Application Files ---
echo "[+] Creating common_crawl_bulk_collector.py application file..."
cp /home/tdf/common_crawl_bulk_collector.py $PROJECT_DIR/common_crawl_bulk_collector.py

# --- 5. Create requirements.txt file ---
echo "[+] Creating requirements.txt file..."
cat << 'EOF' > $PROJECT_DIR/requirements.txt
requests
beautifulsoup4
warcio
lxml
EOF

# --- 6. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 7. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/common_crawl_bulk_collector_v5.service
[Unit]
Description=Common Crawl Bulk Collector Service v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 common_crawl_bulk_collector.py
Restart=on-failure
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF"

# --- 8. Start the Service ---
echo "[+] Starting Common Crawl Bulk Collector service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $RAW_DUMP_DIR
sudo chown -R $USER:$USER $(dirname $DB_PATH)
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start common_crawl_bulk_collector_v5
sudo systemctl enable common_crawl_bulk_collector_v5

echo "--- Common Crawl Bulk Collector Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status common_crawl_bulk_collector_v5"
echo "To watch the logs, run: tail -f /factory/logs/common_crawl_bulk_collector.log"
