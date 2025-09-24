#!/bin/bash
set -e

echo "--- Setting up Ethical Sorter v5 ---"

# --- 1. Define Paths ---
PROJECT_DIR="/factory/workers/sorters/ethical_sorter_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/ethical_sorter.log"
INBOX_DIR="/factory/data/raw_sort"
PROCESSED_DIR="/factory/data/processed_clean"
DISCARDED_DIR="/factory/data/discarded/unsafe_content"
USER="tdf"

# --- 2. System Prerequisites ---
echo "[+] Installing prerequisites (python3-pip, python3-venv)..."
sudo apt-get update
sudo apt-get install -y python3-pip python3-venv

# --- 3. Create Directories ---
echo "[+] Creating project and data directories..."
mkdir -p $PROJECT_DIR
mkdir -p $PROCESSED_DIR
mkdir -p $DISCARDED_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE

# --- 4. Create Application Files ---
echo "[+] Creating ethical_sorter.py application file..."
cp /home/tdf/ethical_sorter.py $PROJECT_DIR/ethical_sorter.py

cat << 'EOF' > $PROJECT_DIR/requirements.txt
spacy
detoxify
EOF

# --- 5. Set Up Python Environment ---
echo "[+] Setting up Python environment (this may take a while)..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install --upgrade pip
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt
echo "[+] Downloading spaCy model..."
$PROJECT_DIR/venv/bin/python -m spacy download en_core_web_sm

# --- 6. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/ethical_sorter_v5.service
[Unit]
Description=Ethical Sorter Service v5
After=network-online.target
Requires=network-online.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 ethical_sorter.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 7. Start the Service ---
echo "[+] Setting permissions and starting Ethical Sorter service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $INBOX_DIR
sudo chown -R $USER:$USER $PROCESSED_DIR
sudo chown -R $USER:$USER $DISCARDED_DIR
sudo chown $USER:$USER $LOG_FILE
sudo systemctl daemon-reload
sudo systemctl start ethical_sorter_v5
sudo systemctl enable ethical_sorter_v5

echo "--- Ethical Sorter Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status ethical_sorter_v5"
echo "To watch the logs, run: tail -f /factory/logs/ethical_sorter.log"
