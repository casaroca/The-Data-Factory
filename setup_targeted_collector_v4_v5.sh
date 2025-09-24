#!/bin/bash
set -e

echo "--- Setting up Targeted Ebook Collector v4 (Multi-Format) v5 ---"

# --- 1. Stop and remove all old versions to prevent conflicts ---
echo "[+] Stopping and removing all old targeted_collector services..."
sudo systemctl stop targeted_collector targeted_collector_v2 targeted_collector_v3 || true
sudo systemctl disable targeted_collector targeted_collector_v2 targeted_collector_v3 || true
sudo rm -f /etc/systemd/system/targeted_collector.service
sudo rm -f /etc/systemd/system/targeted_collector_v2.service
sudo rm -f /etc/systemd/system/targeted_collector_v3.service
sudo rm -rf /factory/workers/collectors/targeted_collector
sudo rm -rf /factory/workers/collectors/targeted_collector_v2
sudo rm -rf /factory/workers/collectors/targeted_collector_v3
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/targeted_collector_v4_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/targeted_collector_v4.log"
BOOK_DEPOSIT_DIR="/library/book_deposit"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project directories..."
mkdir -p $PROJECT_DIR
mkdir -p $BOOK_DEPOSIT_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE

# --- 4. Create Application Files ---
echo "[+] Creating targeted_collector_v4.py application file..."
cp /home/tdf/targeted_collector_v4.py $PROJECT_DIR/targeted_collector_v4.py

# --- 5. Create requirements.txt file ---
echo "[+] Creating requirements.txt file..."
cat << 'EOF' > $PROJECT_DIR/requirements.txt
requests
beautifulsoup4
EOF

# --- 6. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 7. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/targeted_collector_v4_v5.service
[Unit]
Description=Targeted Ebook Collector Service v4 v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 targeted_collector_v4.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 8. Start the Service ---
echo "[+] Starting Targeted Ebook Collector service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $BOOK_DEPOSIT_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start targeted_collector_v4_v5
sudo systemctl enable targeted_collector_v4_v5

echo "--- Targeted Ebook Collector v4 Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status targeted_collector_v4_v5"
echo "To watch the logs, run: tail -f /factory/logs/targeted_collector_v4.log"
