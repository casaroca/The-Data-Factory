#!/bin/bash
set -e

echo "--- Setting up Business Collector ---"

# --- 1. Define Directory Structure ---
PROJECT_DIR="/factory/workers/collectors/business_collector_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/business_collector.log"
DUMP_DIR="/factory/data/raw/business_collector"
USER="tdf"

# --- 2. Create Directories with Permissions ---
echo "[+] Creating project and data directories..."
rm -rf $PROJECT_DIR # Ensure clean project directory
mkdir -p $PROJECT_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE
mkdir -p $DUMP_DIR

# --- 3. Create Application Files ---
echo "[+] Creating Business Collector application files..."
cp /home/tdf/business_collector.py $PROJECT_DIR/business_collector.py

cat << 'EOF' > $PROJECT_DIR/requirements.txt
requests
feedparser
beautifulsoup4
EOF

# --- 4. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt
$PROJECT_DIR/venv/bin/pip install certifi # Explicitly install certifi

# --- 5. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/business_collector_v5.service
[Unit]
Description=Business Collector Service
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 business_collector.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 6. Start the Service ---
echo "[+] Starting Business Collector service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $DUMP_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start business_collector_v5
sudo systemctl enable business_collector_v5

echo "--- Business Collector Setup Complete ---"
echo "To check the status, run: sudo systemctl status business_collector_v5"
echo "To watch the logs, run: tail -f /factory/logs/business_collector.log"