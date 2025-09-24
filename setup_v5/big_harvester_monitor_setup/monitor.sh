#!/bin/bash
echo "=== Big Harvester v1 Status ==="
echo ""
echo "Service Status:"
sudo systemctl status big_harvester_v1 --no-pager -l
echo -e "\nLast 10 log entries:"
tail -n 10 /factory/logs/big_harvester_v1.log
echo -e "\nDisk Usage:"
df -h /mnt/harvested_data
echo -e "\nMemory Usage:"
free -h
echo -e "\nDatabase Stats (Today):"
sqlite3 /factory/db/big_harvester_log.db "SELECT date, archives_processed, ROUND(total_gb, 2) as size_gb FROM daily_stats WHERE date = date('now');"
