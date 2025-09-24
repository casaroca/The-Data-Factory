#!/bin/bash
set -e

echo "--- Setting up YouTube Transcriber v3 (Final Version) v5 ---"

# --- 1. Stop and remove all old versions to prevent conflicts ---
echo "[+] Stopping and removing all old youtube_transcriber services..."
sudo systemctl stop youtube_transcriber || true
sudo systemctl disable youtube_transcriber || true
sudo rm -f /etc/systemd/system/youtube_transcriber.service
sudo rm -rf /factory/workers/extractors/youtube_transcriber
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/extractors/youtube_transcriber_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/youtube_transcriber.log"
DUMP_DIR="/factory/data/raw/youtube_transcripts"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $DUMP_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE

# --- 4. Create Application Files ---
echo "[+] Creating youtube_transcriber.py application file..."
cp /home/tdf/youtube_transcriber.py $PROJECT_DIR/youtube_transcriber.py

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
# THE FIX: Completely remove the old virtual environment to ensure a clean install
rm -rf $PROJECT_DIR/venv
python3 -m venv $PROJECT_DIR/venv
cat << 'EOF' > $PROJECT_DIR/requirements.txt
requests
youtube-transcript-api
google-api-python-client
EOF
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/youtube_transcriber_v5.service
[Unit]
Description=YouTube Transcriber Service v5
After=network.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 youtube_transcriber.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Starting YouTube Transcriber service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $DUMP_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start youtube_transcriber_v5
sudo systemctl enable youtube_transcriber_v5

echo "--- YouTube Transcriber (Final) Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status youtube_transcriber_v5"
echo "To watch the logs, run: tail -f /factory/logs/youtube_transcriber.log"