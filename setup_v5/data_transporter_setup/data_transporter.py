import os
import time
import logging
import subprocess

# --- Configuration ---
LOG_DIR = "/factory/logs"
DESTINATION_DIR = "/factory/data/inbox/" # Note the trailing slash

# --- OVH Server Details: IMPORTANT - EDIT THESE VALUES ---
OVH_USER = "your_user_on_ovh"
OVH_IP = "your_ovh_server_ip"
OVH_SOURCE_DIR = "/path/to/your/data/" # Note the trailing slash
SSH_KEY_PATH = "/home/tdf/.ssh/id_rsa" # Path to the key on the TDF server

# --- Setup Logging ---
os.makedirs(LOG_DIR, exist_ok=True)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'data_transporter.log'), level=logging.INFO, format='%(asctime)s - %(message)s')
logging.getLogger('').addHandler(logging.StreamHandler())

def sync_data():
    """Uses rsync to securely transfer data from OVH."""
    logging.info("Starting data sync from OVH server...")
    
    # Construct the rsync command
    # -a: archive mode (preserves permissions, etc.)
    # -v: verbose
    # -z: compress file data during the transfer
    # --progress: show progress during transfer
    # --remove-source-files: delete files from OVH after they are successfully transferred
    # -e: specifies the ssh command to use, including the identity file
    rsync_cmd = [
        "rsync",
        "-avz",
        "--progress",
        "--remove-source-files",
        "-e", f"ssh -i {SSH_KEY_PATH}",
        f"{OVH_USER}@{OVH_IP}:{OVH_SOURCE_DIR}",
        DESTINATION_DIR
    ]
    
    try:
        # We run this as a blocking call. The service will wait until rsync is done.
        result = subprocess.run(rsync_cmd, capture_output=True, text=True, check=True)
        logging.info("Rsync process completed successfully.")
        logging.info(result.stdout)
        # Check if any files were transferred
        if "total size is 0" in result.stdout:
            return False # No files were transferred
        return True # Files were transferred
    except subprocess.CalledProcessError as e:
        logging.error("Rsync process failed.")
        logging.error(f"Return code: {e.returncode}")
        logging.error(f"Stdout: {e.stdout}")
        logging.error(f"Stderr: {e.stderr}")
        return False

def main():
    while True:
        logging.info("--- Starting new Data Transporter cycle ---")
        
        files_transferred = sync_data()
        
        if not files_transferred:
            logging.info("No files left to transfer on OVH server. Transporter is now idle.")
            # Sleep for a long time since there's nothing left to do
            time.sleep(60 * 60) # Check again in 1 hour
        else:
            logging.info("--- Cycle finished. Starting next sync immediately. ---")

if __name__ == "__main__":
    main()
