#!/bin/bash
set -e

echo "--- Setting up Jr. Librarian (with Advanced Salvage) v5 ---"

# --- 1. Stop and remove the old service to prevent conflicts ---
echo "[+] Stopping and removing old jr_librarian service..."
sudo systemctl stop jr_librarian || true
sudo systemctl disable jr_librarian || true
sudo rm -f /etc/systemd/system/jr_librarian.service
sudo rm -rf /factory/workers/organizers/jr_librarian
sudo systemctl daemon-reload

# --- 2. Define Paths ---
PROJECT_DIR="/factory/workers/organizers/jr_librarian_v5"
LOG_DIR="/factory/logs"
LOG_FILE="$LOG_DIR/jr_librarian.log"
DB_PATH="/factory/db/library.db"
DB_DIR="$(dirname $DB_PATH)"
INBOX_DIR="/factory/library/book_deposit"
LIBRARY_DIR="/factory/library/library"
DISCARD_BIN="/factory/library/discarded"
UNSALVAGEABLE_DIR="/factory/library/unsalvageable"
MEDIA_DIR="/factory/library/media_for_processing"
HTML_DIR="/factory/data/raw/html_from_library"
SALVAGED_TEXT_DIR="/factory/data/raw/salvaged_text"
USER="tdf"

# --- 3. Create Directories ---
echo "[+] Creating project and data directories..."
rm -rf $PROJECT_DIR # Ensure clean project directory
mkdir -p $PROJECT_DIR
mkdir -p $MEDIA_DIR
mkdir -p $HTML_DIR
mkdir -p $UNSALVAGEABLE_DIR
mkdir -p $SALVAGED_TEXT_DIR
mkdir -p $LOG_DIR
touch $LOG_FILE
mkdir -p $DB_DIR
mkdir -p $INBOX_DIR
mkdir -p $LIBRARY_DIR
mkdir -p $DISCARD_BIN

# --- 4. Create Application Files ---
echo "[+] Creating jr_librarian.py application file..."
cp /home/tdf/jr_librarian.py $PROJECT_DIR/jr_librarian.py

# --- 5. Install Required System Tools ---
echo "[+] Installing required system tools for text conversion..."
sudo apt-get update
sudo apt-get install -y poppler-utils libreoffice lynx w3m unrtf

# --- 6. Set Up Python Environment ---
echo "[+] Setting up Python environment..."
python3 -m venv $PROJECT_DIR/venv
$PROJECT_DIR/venv/bin/pip install --upgrade pip
cat << 'EOF' > $PROJECT_DIR/requirements.txt
Pillow
EOF
$PROJECT_DIR/venv/bin/pip install -r $PROJECT_DIR/requirements.txt

# --- 7. Create Service File ---
echo "[+] Creating systemd service file..."
sudo bash -c "cat << EOF > /etc/systemd/system/jr_librarian_v5.service
[Unit]
Description=Jr. Librarian Service (with Salvage) v5
After=network-online.target

[Service]
User=$USER
Group=$USER
WorkingDirectory=$PROJECT_DIR
ExecStart=$PROJECT_DIR/venv/bin/python3 jr_librarian.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF"

# --- 8. Start the Service ---
echo "[+] Starting Jr. Librarian service..."
sudo chown -R $USER:$USER $PROJECT_DIR
sudo chown -R $USER:$USER $MEDIA_DIR
sudo chown -R $USER:$USER $HTML_DIR
sudo chown -R $USER:$USER $UNSALVAGEABLE_DIR
sudo chown -R $USER:$USER $SALVAGED_TEXT_DIR
sudo chown $USER:$USER $LOG_FILE
sudo chown -R $USER:$USER $DB_DIR
sudo chown -R $USER:$USER $INBOX_DIR
sudo chown -R $USER:$USER $LIBRARY_DIR
sudo chown -R $USER:$USER $DISCARD_BIN
sudo systemctl daemon-reload
sudo systemctl start jr_librarian_v5
sudo systemctl enable jr_librarian_v5

echo "--- Jr. Librarian Setup Complete v5 ---"
echo "To check the status, run: sudo systemctl status jr_librarian_v5"
echo "To watch the logs, run: tail -f /factory/logs/jr_librarian.log"
