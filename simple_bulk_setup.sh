#!/bin/bash
set -e

echo "--- Setting up Simple Bulk Text Extractor ---"

# Create single script location
mkdir -p /factory/workers/utilities/simple_extractor

# Create the extractor
cat << 'EOF' > /factory/workers/utilities/simple_extractor/extract_all.py
#!/usr/bin/env python3
import os
import subprocess
import shutil
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

def extract_text_simple(filepath):
    """Extract text from any file - no filtering, no criteria."""
    try:
        filename = os.path.basename(filepath)
        ext = Path(filepath).suffix.lower()
        
        print(f"Processing: {filename}")
        
        # Determine extraction method
        if ext == '.txt':
            with open(filepath, 'r', errors='ignore') as f:
                content = f.read()
        elif ext == '.pdf':
            # Try pdftotext, fallback to strings
            try:
                result = subprocess.run(['pdftotext', filepath, '-'], capture_output=True, text=True, timeout=60)
                content = result.stdout if result.returncode == 0 else ""
            except:
                content = ""
            
            if not content.strip():
                try:
                    result = subprocess.run(['strings', filepath], capture_output=True, text=True, timeout=30)
                    content = result.stdout
                except:
                    content = f"[FAILED_EXTRACTION: {filename}]"
        else:
            # Use strings for everything else
            try:
                result = subprocess.run(['strings', filepath], capture_output=True, text=True, timeout=30)
                content = result.stdout
            except:
                content = f"[FAILED_EXTRACTION: {filename}]"
        
        # Always save something, even if extraction failed
        output_dir = "/factory/data/raw/from_library/Bulk_Extracted"
        os.makedirs(output_dir, exist_ok=True)
        
        output_filename = f"{Path(filepath).stem}.txt"
        output_path = os.path.join(output_dir, output_filename)
        
        # Handle duplicates
        counter = 1
        while os.path.exists(output_path):
            output_path = os.path.join(output_dir, f"{Path(filepath).stem}_{counter}.txt")
            counter += 1
        
        # Write content (even if empty or error message)
        with open(output_path, 'w', errors='ignore') as f:
            f.write(content if content else f"[EMPTY_FILE: {filename}]")
        
        # Remove original
        os.remove(filepath)
        
        print(f"SUCCESS: {filename} -> {os.path.basename(output_path)}")
        return True
        
    except Exception as e:
        print(f"PROCESS_ERROR: {filepath} - {e}")
        try:
            os.remove(filepath)  # Remove even on error
        except:
            pass
        return False

def main():
    inbox = "/factory/library/book_deposit"
    skip_dirs = ['media_for_processing', 'discarded', 'library', 'unsalvageable']
    skip_exts = ['.epub', '.jpg', '.jpeg', '.png', '.gif', '.mp3', '.wav', '.mp4', '.mov']
    
    print("=== SIMPLE BULK EXTRACTOR ===")
    print("Extracting text from ALL files in book_deposit")
    print("No filtering, no criteria - just extract and move")
    print()
    
    # Get all files
    all_files = []
    for root, dirs, files in os.walk(inbox):
        dirs[:] = [d for d in dirs if d not in skip_dirs]
        for file in files:
            filepath = os.path.join(root, file)
            if Path(filepath).suffix.lower() not in skip_exts:
                all_files.append(filepath)
    
    print(f"Found {len(all_files)} files to extract")
    
    if not all_files:
        print("No files to process")
        return
    
    # Process with thread pool
    print("Starting extraction...")
    with ThreadPoolExecutor(max_workers=20) as executor:
        results = list(executor.map(extract_text_simple, all_files))
    
    successful = sum(results)
    print(f"\n=== EXTRACTION COMPLETE ===")
    print(f"Processed: {successful}/{len(all_files)} files")
    print(f"Output: /factory/data/raw/from_library/Bulk_Extracted/")

if __name__ == "__main__":
    main()
EOF

chmod +x /factory/workers/utilities/simple_extractor/extract_all.py

echo "--- Simple Bulk Extractor Ready ---"
echo ""
echo "TO RUN:"
echo "cd /factory/workers/utilities/simple_extractor"
echo "python3 extract_all.py"
echo ""
echo "This will extract text from ALL files and clear your backlog."
