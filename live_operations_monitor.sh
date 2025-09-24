#!/bin/bash

# An advanced monitor that shows the live status and last log line for each worker.

# --- Configuration ---
SERVICES=(
    "jr_librarian_v5"
    "archive_org_harvester_v2_v5"
    "archive_org_query_collector_v5"
    "arxiv_harvester_v3_v5"
    "common_crawl_bulk_collector_v5"
    "common_crawl_harvester_v2_v5"
    "common_crawl_harvester_v3_v5"
    "common_crawl_query_collector_v5"
    "data_collector_v2_v5"
    "dpla_harvester_v5"
    "ethical_sorter_v5"
    "data_processor_v5"
    "discard_processor_v5"
    "data_packager_v5"
    "image_processor_v5"
    "info_collector_v2_v5"
    "language_collector_v2_v5"
    "main_archiver_v5"
    "media_processor_v5"
    "salvage_extractor_v5"
    "smart_router_collector_v5"
    "social_media_scraper_v5"
    "topic_puller_v5"
)
LOG_DIR="/factory/logs"

# --- Helper function to format bytes to human-readable size ---
format_bytes() {
    local bytes=$1
    local units=("B" "KB" "MB" "GB" "TB")
    local i=0
    local size=$bytes

    while (( $(echo "$size >= 1024" | bc -l) )) && (( i < ${#units[@]} - 1 )); do
        size=$(echo "scale=2; $size / 1024" | bc -l)
        i=$((i + 1))
    done
    printf "%.1f %s" "$size" "${units[$i]}"
}

# --- Main Loop ---
while true; do
    clear
    
    # --- Header ---
    echo "========================================================================================================================"
    echo "                                    Next GenAi Data Factory - Live Operations Monitor"
    echo "========================================================================================================================"
    date
    echo ""

    # --- Service Status Header ---
    printf "% -30s | % -10s | %s\n" "Worker Service" "Status" "Latest Activity"
    echo "------------------------------------------------------------------------------------------------------------------------"

    # --- Service Status Loop ---
    for service in "${SERVICES[@]}"; do
        status="Stopped"
        # Remove the _vX suffix from the service name to get the correct log file name
        log_file_base=$(echo "$service" | sed 's/_v[0-9]*$//')
        log_file="$LOG_DIR/${log_file_base}.log"
        last_log_line="-"

        if systemctl is-active --quiet "$service"; then
            status="Running"
        fi
        
        if [ -r "$log_file" ]; then
            last_log_line=$(tail -n 1 "$log_file" | cut -c -120)
        else
            last_log_line="Log not yet created."
        fi
        
        printf "% -30s | % -10s | %s\n" "$service" "$status" "$last_log_line"
    done
    
    echo ""
    echo "------------------------------------------------------------------------------------------------------------------------"
    echo "--- Data Pipeline Storage ---"
    
    # Calculate directory sizes in bytes and format them
    RAW_BYTES=$(du -sb /factory/data/raw 2>/dev/null | awk '{print $1}')
    PROCESSED_BYTES=$(du -sb /factory/data/processed 2>/dev/null | awk '{print $1}')
    FINAL_BYTES=$(du -sb /factory/data/final 2>/dev/null | awk '{print $1}')
    RAW_SORT_BYTES=$(du -sb /factory/data/raw_sort 2>/dev/null | awk '{print $1}')

    printf "  /factory/data/raw: %s\n" "$(format_bytes $RAW_BYTES)"
    printf "  /factory/data/processed: %s\n" "$(format_bytes $PROCESSED_BYTES)"
    printf "  /factory/data/final: %s\n" "$(format_bytes $FINAL_BYTES)"
    printf "  /factory/data/raw_sort: %s\n" "$(format_bytes $RAW_SORT_BYTES)"

    sleep 5
done
