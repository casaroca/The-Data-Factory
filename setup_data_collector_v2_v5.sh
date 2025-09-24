#!/bin/bash
set -e

echo "--- Setting up Data Collector v2 v5 ---"

# --- 1. Stop and remove the old service to prevent conflicts ---
echo "[+] Stopping and removing old data_collector service..."
sudo systemctl stop data_collector || true
sudo systemctl disable data_collector || true
sudo rm -f /etc/systemd/system/data_collector.service
sudo rm -rf /factory/workers/collectors/data_collector
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/data_collector_v2_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/data_collector_v2.log"
DUMP_DIR="/factory/data/raw"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project directories..."
mkdir -p $PROJECT_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE

# --- 4. Create Application Files ---
echo "[+] Creating data_collector_v2.py application file..."
cp /home/tdf/data_collector_v2.py $PROJECT_DIR/data_collector_v2.py

# --- 5. Create requirements.txt file ---
echo "[+] Creating requirements.txt file..."
cat << 'EOF' > $PROJECT_DIR/requirements.txt
requests
feedparser
EOF

# --- 6. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 7. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/data_collector_v2_v5.service
[Unit]
Description=Data Collector Service v2 v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 data_collector_v2.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 8. Start the Service ---
echo "[+] Starting Data Collector v2 service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $DUMP_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start data_collector_v2_v5
sudo systemctl enable data_collector_v2_v5

echo "--- Data Collector v2 Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status data_collector_v2_v5"
echo "To watch the logs, run: tail -f /factory/logs/data_collector_v2.log"
