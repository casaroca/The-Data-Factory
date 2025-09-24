#!/bin/bash
set -e

echo "--- Setting up Archive.org Query Collector v5 ---"

# --- 1. Stop and remove ALL old targeted_collector versions ---
echo "[+] Stopping and removing all old targeted_collector services..."
sudo systemctl stop targeted_collector* || true
sudo systemctl disable targeted_collector* || true
sudo rm -f /etc/systemd/system/targeted_collector*.service
sudo rm -rf /factory/workers/collectors/targeted_collector*
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/archive_org_query_collector_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/archive_org_query_collector.log"
BOOK_DEPOSIT_DIR="/library/book_deposit"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project directories..."
mkdir -p $PROJECT_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE

# --- 4. Create Application Files ---
echo "[+] Creating archive_org_query_collector.py application file..."
cp /home/tdf/archive_org_query_collector.py $PROJECT_DIR/archive_org_query_collector.py

# --- 5. Create requirements.txt file ---
echo "[+] Creating requirements.txt file..."
cat << 'EOF' > $PROJECT_DIR/requirements.txt
requests
beautifulsoup4
lxml
EOF

# --- 6. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 7. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/archive_org_query_collector_v5.service
[Unit]
Description=Archive.org Query Collector Service v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 archive_org_query_collector.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 8. Start the Service ---
echo "[+] Starting Archive.org Query Collector service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $BOOK_DEPOSIT_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start archive_org_query_collector_v5
sudo systemctl enable archive_org_query_collector_v5

echo "--- Archive.org Query Collector Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status archive_org_query_collector_v5"
echo "To watch the logs, run: tail -f /factory/logs/archive_org_query_collector.log"
