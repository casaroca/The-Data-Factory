#!/bin/bash
set -e

echo "--- Setting up Main Archiver v5 ---"

# --- 1. Define Paths ---
PROJECT_DIR="/factory/workers/archivers/main_archiver_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/main_archiver.log"
SOURCE_DIR="/factory/data/raw"
ARCHIVE_COPY_DIR="/mnt/archive"
DESTINATION_SORT_DIR="/factory/data/raw_sort"
USER="tdf"

# --- 2. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE
mkdir -p $SOURCE_DIR
mkdir -p $ARCHIVE_COPY_DIR
mkdir -p $DESTINATION_SORT_DIR

# --- 3. Application File (Assume already in place or handle separately) ---
echo "[+] Creating main_archiver.py application file..."
cp /home/tdf/main_archiver.py $PROJECT_DIR/main_archiver.py

# --- 4. Create requirements.txt (if any, for now it's empty) ---
cat << 'EOF' > $PROJECT_DIR/requirements.txt
# No external pip packages needed for now
EOF

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
rm -rf $PROJECT_DIR/venv # ADDED: Remove existing venv
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install --upgrade pip
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/main_archiver_v5.service
[Unit]
Description=Main Archiver Service v5
After=network-online.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 main_archiver.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Setting permissions and starting Main Archiver service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $LOG_DIR
sudo chown -R $USER:$USER $SOURCE_DIR
sudo chown -R $USER:$USER $ARCHIVE_COPY_DIR
sudo chown -R $USER:$USER $DESTINATION_SORT_DIR
sudo systemctl daemon-reload
sudo systemctl start main_archiver_v5
sudo systemctl enable main_archiver_v5

echo "--- Main Archiver Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status main_archiver_v5"
echo "To watch the logs, run: tail -f /factory/logs/main_archiver.log"
