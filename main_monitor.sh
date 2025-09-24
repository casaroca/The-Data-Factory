#!/bin/bash

# A dedicated monitor for the main data factory node.

# --- Configuration ---
# This is the complete list of all services running on the main factory node
SERVICES=(
    # Organizers & Extractors
    "jr_librarian_v5"
    # Collectors
    "archive_org_harvester_v2_v5"
    "archive_org_query_collector_v5"
    "arxiv_harvester_v3_v5"
    "common_crawl_bulk_collector_v5"
    "common_crawl_harvester_v2_v5"
    "common_crawl_harvester_v3_v5"
    "common_crawl_query_collector_v5"
    "data_collector_v2_v5"
    "dpla_harvester_v5"
    "info_collector_v2_v5"
    # Sorters
    "ethical_sorter_v5"
    # Processors
    "data_processor_v5"
    "discard_processor_v5"
    "data_packager_v5"
    "image_processor_v5"
    # Utilities
    "main_archiver_v5"
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
    printf "%30s | %10s | %s\n" "Worker Service" "Status" "Latest Activity"
    echo "------------------------------------------------------------------------------------------------------------------------"

    # --- Service Status Loop ---
    for service in "${SERVICES[@]}"; do
        status="Stopped"
        # THE FIX: Remove the _v5 suffix from the service name to get the correct log file name
        log_file_base=$(echo "$service" | sed 's/_v[0-9]*$//')
        log_file="$LOG_DIR/${log_file_base}.log"
        last_log_line="-"

        if systemctl is-active --quiet "$service"; then
            status="Running"
        fi
        
        if [ -r "$log_file" ]; then
            last_log_line=$(tail -n 1 "$log_file" | cut -c -120) # Truncate long lines for display
        else
            last_log_line="Log not yet created."
        fi
        
        printf "%30s | %10s | %s\n" "$service" "$status" "$last_log_line"
    done
    
    echo ""
    echo "------------------------------------------------------------------------------------------------------------------------"
    echo "--- Data Pipeline Storage ---"
    # Use du to show the size of the key data directories
    du -sh /factory/data/raw /factory/data/processed /factory/data/final 2>/dev/null | awk '{print "  " $2 ": " $1}'
    
    sleep 5
done