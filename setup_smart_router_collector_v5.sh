#!/bin/bash
set -e

echo "--- Setting up Smart Router Collector v5 ---"

# --- 1. Define Paths ---
PROJECT_DIR="/factory/workers/collectors/smart_router_collector_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/smart_router_collector.log"
RAW_TEXT_DIR="/factory/data/raw/routed_text_html"
BOOK_DEPOSIT_DIR="/factory/library/book_deposit"
GEM_INBOX_DIR="/factory/data/inbox/gem_files"
USER="tdf"

# --- 2. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $RAW_TEXT_DIR
mkdir -p $BOOK_DEPOSIT_DIR
mkdir -p $GEM_INBOX_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE

# --- 3. Create Application Files ---
echo "[+] Creating smart_router_collector.py application file..."
cp /home/tdf/smart_router_collector.py $PROJECT_DIR/smart_router_collector.py

# --- 4. Create requirements.txt file ---
echo "[+] Creating requirements.txt file..."
cat << 'EOF' > $PROJECT_DIR/requirements.txt
requests
beautifulsoup4
EOF

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/smart_router_collector_v5.service
[Unit]
Description=Smart Router Collector Service v5
After=network-online.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 smart_router_collector.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting Smart Router Collector service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $RAW_TEXT_DIR
sudo chown -R $USER:$USER $BOOK_DEPOSIT_DIR
sudo chown -R $USER:$USER $GEM_INBOX_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start smart_router_collector_v5
sudo systemctl enable smart_router_collector_v5

echo "--- Smart Router Collector Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status smart_router_collector_v5"
echo "To watch the logs, run: tail -f /factory/logs/smart_router_collector.log"
