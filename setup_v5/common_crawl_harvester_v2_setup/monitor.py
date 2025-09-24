#!/usr/bin/env python3
import sqlite3
import os
from datetime import datetime

DB_PATH = "/factory/db/common_crawl_log.db"
RAW_DUMP_DIR = "/factory/data/raw/common_crawl_harvest"

def get_stats():
    if not os.path.exists(DB_PATH):
        print("Database not found. Service may not be running yet.")
        return
    
    with sqlite3.connect(DB_PATH) as conn:
        c = conn.cursor()
        
        # Today's stats
        today = datetime.now().strftime('%Y-%m-%d')
        c.execute("SELECT * FROM daily_stats WHERE date = ?", (today,))
        today_stats = c.fetchone()
        
        # Total stats
        c.execute("SELECT COUNT(*), AVG(file_size), SUM(pages_extracted) FROM processed_archives")
        total_stats = c.fetchone()
        
        # Recent activity
        c.execute("SELECT path, processed_date, file_size/1024/1024 as size_mb, pages_extracted" 
                    " FROM processed_archives" 
                    " ORDER BY processed_date DESC LIMIT 5")
        recent = c.fetchall()
    
    print("=== Common Crawl Harvester Status ===")
    print(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    if today_stats:
        print(f"\nToday's Progress:")
        print(f"  Archives processed: {today_stats[1]}")
        print(f"  Data harvested: {today_stats[2]:.1f} GB")
        print(f"  Pages extracted: {today_stats[3]:,}")
    else:
        print("\nNo activity today yet.")
    
    if total_stats[0]:
        print(f"\nTotal Statistics:")
        print(f"  Total archives: {total_stats[0]}")
        print(f"  Average size: {total_stats[1]/1024/1024:.1f} MB")
        print(f"  Total pages: {total_stats[2]:,}")
    
    if recent:
        print(f"\nRecent Activity:")
        for path, date, size_mb, pages in recent:
            filename = os.path.basename(path)
            print(f"  {date}: {filename} ({size_mb:.1f}MB, {pages} pages)")
    
    # Check output directory
    if os.path.exists(RAW_DUMP_DIR):
        files = [f for f in os.listdir(RAW_DUMP_DIR) if f.endswith('.txt')]
        total_size = sum(os.path.getsize(os.path.join(RAW_DUMP_DIR, f)) for f in files)
        print(f"\nOutput Files:")
        print(f"  Files created: {len(files)}")
        print(f"  Total output size: {total_size/1024/1024:.1f} MB")

if __name__ == "__main__":
    get_stats()
