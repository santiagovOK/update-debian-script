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

# Function to check for distribution upgrades
check_distribution_upgrade() {
    # Get current version information
    current_version=$(lsb_release -r | awk '{print $2}')
    current_codename=$(lsb_release -c | awk '{print $2}')
    
    log_message "Current Debian version: $current_version ($current_codename)"
    
    # Check if there's a newer stable release available
    # This checks the Debian sources for newer releases
    available_upgrades=$(sudo apt list --upgradable 2>/dev/null | grep -i "debian-archive-keyring\|base-files" | wc -l)
    
    # Alternative method: check for newer release in sources.list.d or main sources
    if [ -f /etc/apt/sources.list ]; then
        # Look for stable/testing/unstable indicators that might suggest upgrade availability
        newer_release_available=false
        
        # Check if do-release-upgrade equivalent exists (not standard on Debian, but we can simulate)
        # Check for newer version by examining available base-files package
        base_files_version=$(apt-cache policy base-files | grep "Candidate:" | awk '{print $2}')
        installed_base_files=$(apt-cache policy base-files | grep "Installed:" | awk '{print $2}')
        
        if [ "$base_files_version" != "$installed_base_files" ] && [ "$base_files_version" != "(none)" ]; then
            # Extract version numbers for comparison
            candidate_major=$(echo $base_files_version | cut -d. -f1)
            installed_major=$(echo $installed_base_files | cut -d. -f1)
            
            if [ "$candidate_major" -gt "$installed_major" ] 2>/dev/null; then
                newer_release_available=true
                new_version=$candidate_major
            fi
        fi
        
        # Additional check: parse available releases from debian repositories
        if ! $newer_release_available; then
            # Check if there are references to newer stable releases
            if grep -q "bookworm" /etc/apt/sources.list* 2>/dev/null && [ "$current_codename" = "bullseye" ]; then
                newer_release_available=true
                new_version="12 (bookworm)"
            elif grep -q "trixie" /etc/apt/sources.list* 2>/dev/null && [ "$current_codename" = "bookworm" ]; then
                newer_release_available=true
                new_version="13 (trixie)"
            fi
        fi
        
        if $newer_release_available; then
            echo ""
            echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
            echo -e "${YELLOW}    DISTRIBUTION UPGRADE AVAILABLE${NC}"
            echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
            echo -e "${BLUE}Current version: ${NC}Debian $current_version ($current_codename)"
            echo -e "${GREEN}Available version: ${NC}Debian $new_version"
            echo ""
            echo -e "${YELLOW}A newer Debian release is available!${NC}"
            echo ""
            
            # Prompt user for distribution upgrade
            while true; do
                echo -e "${BLUE}Do you want to perform a distribution upgrade? ${NC}"
                echo -e "${YELLOW}Warning: This is a major system change that may take significant time${NC}"
                echo -e "${YELLOW}and could potentially cause issues. Ensure you have backups.${NC}"
                echo ""
                read -p "Proceed with distribution upgrade? (y/N): " choice
                
                case $choice in
                    [Yy]* )
                        log_message "User chose to perform distribution upgrade from $current_version to $new_version"
                        return 0  # Proceed with upgrade
                        ;;
                    [Nn]* | "" )
                        log_message "User declined distribution upgrade"
                        echo -e "${BLUE}Distribution upgrade skipped. Continuing with regular updates.${NC}"
                        return 1  # Skip upgrade
                        ;;
                    * )
                        echo -e "${RED}Please answer yes (y) or no (n).${NC}"
                        ;;
                esac
            done
        else
            log_message "No distribution upgrade available"
            return 1  # No upgrade available
        fi
    else
        log_message "Could not check for distribution upgrades - sources.list not found"
        return 1
    fi
}

# Function to perform distribution upgrade
perform_distribution_upgrade() {
    echo ""
    echo -e "${YELLOW}Starting distribution upgrade process...${NC}"
    
    # Update sources.list for the new release if needed
    # This is a simplified approach - in practice, you'd want more sophisticated logic
    echo "Preparing for distribution upgrade..."
    
    # First, ensure all current packages are up to date
    sudo apt update && sudo apt upgrade -y
    
    # Perform the distribution upgrade
    echo "Performing full distribution upgrade..."
    sudo apt full-upgrade -y
    
    if [ $? -eq 0 ]; then
        log_message "Distribution upgrade completed successfully"
        echo -e "${GREEN}Distribution upgrade completed successfully!${NC}"
        echo -e "${YELLOW}Note: A system reboot is recommended to complete the upgrade.${NC}"
        
        # Ask about reboot
        read -p "Do you want to reboot now? (y/N): " reboot_choice
        case $reboot_choice in
            [Yy]* )
                log_message "System reboot initiated by user after distribution upgrade"
                sudo reboot
                ;;
            * )
                echo -e "${YELLOW}Remember to reboot your system when convenient.${NC}"
                ;;
        esac
    else
        log_message "Distribution upgrade failed"
        echo -e "${RED}Distribution upgrade failed. Check logs for details.${NC}"
        return 1
    fi
}

# Start of the script
log_message "Starting the update process."
echo ""

# Check for distribution upgrades first
if check_distribution_upgrade; then
    if perform_distribution_upgrade; then
        # If distribution upgrade was successful, we can skip some regular update steps
        # as they were already performed during the distribution upgrade
        echo ""
        echo -e "${GREEN}Distribution upgrade completed. Performing final cleanup...${NC}"
        
        # Clean up unnecessary packages
        echo "Removing unnecessary packages..."
        sudo apt autoremove -y
        if [ $? -eq 0 ]; then
            log_message "Unnecessary packages removed successfully."
        else
            log_message "Failed to remove unnecessary packages."
        fi
        
        log_message "Update process with distribution upgrade completed."
        echo "Update process with distribution upgrade completed. Check the log at $LOGFILE for details."
        send_notification "Debian distribution upgrade completed successfully!"
        exit 0
    else
        # Distribution upgrade failed, continue with regular updates
        echo -e "${YELLOW}Continuing with regular system updates...${NC}"
    fi
else
    echo -e "${BLUE}No distribution upgrade available or skipped. Proceeding with regular updates.${NC}"
fi

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

# Check if there are any Flatpak packages installed
if flatpak list &> /dev/null; then
    echo "Updating Flatpak packages..."
    if sudo flatpak update -y &> /tmp/flatpak_update.log; then
        log_message "Flatpak packages updated successfully."
    else
        log_message "Failed to update Flatpak packages."
        send_notification "Failed to update Flatpak packages. Check the log at $LOGFILE for details."
        exit 1
    fi
else
    log_message "No Flatpak packages installed. Skipping Flatpak update."
fi
echo ""

# Perform distribution upgrade (regular dist-upgrade, not full version upgrade)
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