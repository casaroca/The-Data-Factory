#!/bin/bash
set -e

echo "--- Setting up Main Data Factory Monitor ---"

# --- 1. Define Paths ---
MONITOR_DIR="/factory/workers/monitors/main_monitor"
LOG_DIR="/factory/logs"
USER="tdf"

# --- 2. Create Directory ---
echo "[+] Creating monitor directory..."
# Remove old monitor directory to ensure a clean install
rm -rf $MONITOR_DIR
mkdir -p $MONITOR_DIR

# --- 3. Create the Monitor Script ---
echo "[+] Creating main_monitor.sh file..."
cat << 'EOF' > $MONITOR_DIR/main_monitor.sh
#!/bin/bash

# A dedicated monitor for the main data factory node.

# --- Configuration ---
# This is the complete list of all services running on the main factory node
SERVICES=(
    # Organizers & Extractors
    "librarian"
    "jr_librarian"
    "topic_puller"
    "gem_extractor"
    "salvage_extractor"
    "youtube_transcriber"
    # Collectors
    "data_collector_v2"
    "language_collector_v2"
    "tech_collector_v2"
    "business_collector_v2"
    "stats_collector_v2"
    "info_collector_v2"
    "ebook_collector_v3"
    "nypl_collector"
    "dpla_harvester"
    "archive_org_query_collector"
    "social_media_scraper"
    # Sorters
    "ethical_sorter"
    # Processors
    "data_processor"
    "discard_processor"
    "data_packager"
    "image_processor"
    # Utilities
    "archiver"
)
LOG_DIR="/factory/logs"

# --- Main Loop ---
while true; do
    clear
    
    # --- Header ---
    echo "========================================================================================================================"
    echo "                                    Next GenAi Data Factory - Main Operations Monitor"
    echo "========================================================================================================================"
    date
    echo ""

    # --- Service Status Header ---
    printf "%-30s | %-10s | %s\n" "Worker Service" "Status" "Latest Activity"
    echo "------------------------------------------------------------------------------------------------------------------------"

    # --- Service Status Loop ---
    for service in "${SERVICES[@]}"; do
        status="Stopped"
        log_file="$LOG_DIR/${service}.log"
        last_log_line="-"

        if systemctl is-active --quiet "$service"; then
            status="Running"
        fi
        
        if [ -r "$log_file" ]; then
            last_log_line=$(tail -n 1 "$log_file" | cut -c -120) # Truncate long lines for display
        else
            last_log_line="Log not yet created."
        fi
        
        printf "%-30s | %-10s | %s\n" "$service" "$status" "$last_log_line"
    done
    
    echo ""
    echo "------------------------------------------------------------------------------------------------------------------------"
    echo "--- Data Pipeline Storage ---"
    # Use du to show the size of the key data directories
    du -sh /factory/data/raw /factory/data/processed /factory/data/final 2>/dev/null | awk '{print "  " $2 ": " $1}'
    
    sleep 5
done
EOF

# --- 4. Make the monitor script executable and set permissions ---
chmod +x $MONITOR_DIR/main_monitor.sh
sudo chown -R $USER:$USER /factory

echo "--- Main Factory Monitor Setup Complete ---"
echo "You can now run the monitor with the command:"
echo "$MONITOR_DIR/main_monitor.sh"
