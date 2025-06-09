#!/bin/bash

# Update Debian Script
# This script automates the process of updating the Debian system.

# Define log file for auditing
LOGFILE="/tmp/update-debian.log"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log_message() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
    # Output colorized message to the console
    case "$1" in
        *"successfully"*)
            echo -e "${GREEN}$1${NC}"
            ;;
        *"Failed"*)
            echo -e "${RED}$1${NC}"
            ;;
        *)
            echo -e "${BLUE}$1${NC}"
            ;;
    esac
}

# Function to send xmessage notification
send_notification() {
    xmessage -timeout 1 -center "$1"
}

# Start of the script
log_message "Starting the update process."
echo ""

# Update package lists
echo "Updating package lists..."
sudo apt update
if [ $? -eq 0 ]; then
    log_message "Package lists updated successfully."
else
    log_message "Failed to update package lists."
    send_notification "Failed to update package lists. Check the log at $LOGFILE for details."
    exit 1
fi

echo ""

# Upgrade installed packages
echo "Upgrading installed packages..."
sudo apt upgrade -y
if [ $? -eq 0 ]; then
    log_message "Installed packages upgraded successfully."
else
    log_message "Failed to upgrade installed packages."
    send_notification "Failed to upgrade installed packages. Check the log at $LOGFILE for details."
    exit 1
fi

echo ""

# Update Flatpak packages
echo "Updating Flatpak packages..."
if sudo flatpak update -y &> /tmp/flatpak_update.log; then
    log_message "Flatpak packages updated successfully."
else
    log_message "Failed to update Flatpak packages."
    send_notification "Failed to update Flatpak packages. Check the log at $LOGFILE for details."
    exit 1
fi

echo ""

# Perform distribution upgrade
echo "Performing distribution upgrade..."
sudo apt dist-upgrade -y
if [ $? -eq 0 ]; then
    log_message "Distribution upgraded successfully."
else
    log_message "Failed to perform distribution upgrade."
    send_notification "Failed to perform distribution upgrade. Check the log at $LOGFILE for details."
    exit 1
fi

echo ""

# Install the updated kernel - Change to 32 bits linux-image if it's required
echo "Installing updated kernel..."
sudo apt install linux-image-amd64 -y
if [ $? -eq 0 ]; then
    log_message "Updated kernel installed successfully."
else
    log_message "Failed to install updated kernel."
    send_notification "Failed to install updated kernel. Check the log at $LOGFILE for details."
    exit 1
fi

echo ""

# Clean up unnecessary packages
echo "Removing unnecessary packages..."
sudo apt autoremove -y
if [ $? -eq 0 ]; then
    log_message "Unnecessary packages removed successfully."
else
    log_message "Failed to remove unnecessary packages."
    send_notification "Failed to remove unnecessary packages. Check the log at $LOGFILE for details."
fi

echo ""

log_message "Update process completed."
echo "Update process completed. Check the log at $LOGFILE for details."

# Send notification to Openbox if no errors occurred
send_notification "The Debian system update process has completed."