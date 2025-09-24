#!/bin/bash
set -e

echo "--- Setting up Topic Puller v5 ---"

# --- 1. Define Paths ---
PROJECT_DIR="/factory/workers/extractors/topic_puller_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/topic_puller.log"
DB_PATH="/factory/db/topic_puller_log.db"
DB_DIR="$(dirname $DB_PATH)"
LIBRARY_DIR="/factory/library/library"
RAW_DUMP_DIR="/factory/data/inbox"
USER="tdf"

# --- 2. System Prerequisites ---
echo "[+] Installing prerequisites (ebooklib, beautifulsoup4, lxml)..."
sudo apt-get update
sudo apt-get install -y python3-pip python3-venv

# --- 3. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $RAW_DUMP_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE
mkdir -p $DB_DIR
mkdir -p $LIBRARY_DIR

# --- 4. Create Application Files ---
echo "[+] Creating topic_puller.py application file..."
cp /home/tdf/topic_puller.py $PROJECT_DIR/topic_puller.py

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install --upgrade pip
cat << 'EOF' > $PROJECT_DIR/requirements.txt
ebooklib
beautifulsoup4
EOF
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/topic_puller_v5.service
[Unit]
Description=Ebook Topic Puller Service v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 topic_puller.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting Topic Puller service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $RAW_DUMP_DIR
sudo chown -R $USER:$USER $DB_DIR
sudo chown -R $USER:$USER $LIBRARY_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start topic_puller_v5
sudo systemctl enable topic_puller_v5

echo "--- Topic Puller Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status topic_puller_v5"
echo "To watch the logs, run: tail -f /factory/logs/topic_puller.log"