#!/bin/bash
# Debian Distribution Upgrade Script
# This script follows official Debian upgrade procedures from release notes

# Define log file for auditing
LOGFILE="/tmp/debian-upgrade.log"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to log messages with colors
log_message() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
    case "$1" in
        *"successfully"*|*"completed"*)
            echo -e "${GREEN}$1${NC}"
            ;;
        *"Failed"*|*"ERROR"*)
            echo -e "${RED}$1${NC}"
            ;;
        *"WARNING"*|*"Warning"*)
            echo -e "${YELLOW}$1${NC}"
            ;;
        *"INFO"*)
            echo -e "${CYAN}$1${NC}"
            ;;
        *)
            echo -e "${BLUE}$1${NC}"
            ;;
    esac
}

# Function to send notification
send_notification() {
    if command -v xmessage &> /dev/null; then
        xmessage -timeout 3 -center "$1"
    fi
}

# Function to check available disk space
check_disk_space() {
    log_message "INFO: Checking available disk space..."
    
    # Check space in /var (for package cache)
    var_space=$(df /var | awk 'NR==2 {print $4}')
    var_space_gb=$((var_space / 1024 / 1024))
    
    # Check space in / (for system files)
    root_space=$(df / | awk 'NR==2 {print $4}')
    root_space_gb=$((root_space / 1024 / 1024))
    
    log_message "Available space in /var: ${var_space_gb}GB"
    log_message "Available space in /: ${root_space_gb}GB"
    
    if [ "$var_space_gb" -lt 2 ] || [ "$root_space_gb" -lt 3 ]; then
        log_message "WARNING: Insufficient disk space for upgrade"
        echo -e "${RED}Insufficient disk space detected!${NC}"
        echo -e "${YELLOW}Minimum recommended: 2GB in /var, 3GB in /${NC}"
        echo -e "${BLUE}Current: ${var_space_gb}GB in /var, ${root_space_gb}GB in /${NC}"
        return 1
    fi
    return 0
}

# Function to check for non-Debian packages
check_non_debian_packages() {
    log_message "INFO: Checking for non-Debian packages..."
    if ! command -v apt-forktracer &> /dev/null; then
        echo -e "${YELLOW}WARNING: apt-forktracer is not installed. Cannot check for non-debian packages.${NC}"
        echo -e "${BLUE}To install it, run: sudo apt install apt-forktracer${NC}"
        return 0
    fi

    non_debian_packages=$(apt-forktracer | grep -v "^/")
    if [ -n "$non_debian_packages" ]; then
        log_message "WARNING: Non-Debian packages detected"
        echo -e "${YELLOW}Non-Debian packages detected. It is recommended to remove or disable them before upgrading:${NC}"
        echo "$non_debian_packages"
        return 1
    fi
    return 0
}

# Function to check for obsolete packages
check_obsolete_packages() {
    log_message "INFO: Checking for obsolete packages..."
    if ! command -v apt-show-versions &> /dev/null; then
        echo -e "${YELLOW}WARNING: apt-show-versions is not installed. Cannot check for obsolete packages.${NC}"
        echo -e "${BLUE}To install it, run: sudo apt install apt-show-versions${NC}"
        return 0
    fi

    obsolete_packages=$(apt-show-versions | grep "No available version in sources")
    if [ -n "$obsolete_packages" ]; then
        log_message "WARNING: Obsolete packages detected"
        echo -e "${YELLOW}Obsolete packages detected. It is recommended to remove them before upgrading:${NC}"
        echo "$obsolete_packages"
    fi
    return 0
}

# Function to check for recommended packages
check_recommended_packages() {
    log_message "INFO: Checking for recommended packages..."
    for pkg in apt-listbugs apt-listchanges; do
        if ! command -v $pkg &> /dev/null; then
            echo -e "${YELLOW}WARNING: $pkg is not installed. It is highly recommended to install it.${NC}"
            echo -e "${BLUE}To install it, run: sudo apt install $pkg${NC}"
        fi
    done
}

# Function to verify system state
verify_system_state() {
    log_message "INFO: Verifying system state..."
    
    # Check for broken packages
    broken_packages=$(dpkg --audit 2>/dev/null)
    if [ -n "$broken_packages" ]; then
        log_message "ERROR: System has broken packages"
        echo -e "${RED}Broken packages detected. Please fix before upgrading:${NC}"
        echo "$broken_packages"
        return 1
    fi
    
    # Check for held packages
    held_packages=$(apt-mark showhold)
    if [ -n "$held_packages" ]; then
        log_message "WARNING: Held packages detected: $held_packages"
        echo -e "${YELLOW}Held packages found:${NC}"
        echo "$held_packages"
        echo -e "${BLUE}Consider removing holds before upgrading${NC}"
    fi
    
    # Check for non-debian packages
    if ! check_non_debian_packages; then
        echo -e "${YELLOW}Continue anyway? (y/N): ${NC}"
        read -r continue_choice
        if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
            log_message "Upgrade cancelled due to non-debian packages"
            exit 1
        fi
    fi

    # Check for obsolete packages
    check_obsolete_packages

    # Check for recommended packages
    check_recommended_packages

    # Check current Debian version
    current_version=$(cat /etc/debian_version 2>/dev/null || echo "unknown")
    log_message "Current Debian version: $current_version"
    
    return 0
}

# Function to check for distribution upgrades
check_distribution_upgrade() {
    local current_codename current_version available_version
    
    # Get current version information
    if ! command -v lsb_release &> /dev/null; then
        sudo apt update &>/dev/null
        sudo apt install -y lsb-release &>/dev/null
    fi
    
    current_codename=$(lsb_release -c 2>/dev/null | awk '{print $2}' || echo "unknown")
    current_version=$(lsb_release -r 2>/dev/null | awk '{print $2}' || echo "unknown")
    
    log_message "Current Debian: $current_version ($current_codename)"
    
    # Define upgrade paths
    declare -A upgrade_paths=(
        ["bookworm"]="trixie|13"
        ["bullseye"]="bookworm|12"
        ["buster"]="bullseye|11"
    )
    
    # Check if upgrade is available
    if [[ -n "${upgrade_paths[$current_codename]}" ]]; then
        IFS='|' read -r new_codename new_version <<< "${upgrade_paths[$current_codename]}"
        
        echo ""
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║                 DISTRIBUTION UPGRADE AVAILABLE              ║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo -e "${BLUE}Current version:${NC} Debian $current_version ($current_codename)"
        echo -e "${GREEN}Available version:${NC} Debian $new_version ($new_codename)"
        echo ""
        echo -e "${YELLOW}⚠️  IMPORTANT NOTICES:${NC}"
        echo -e "${YELLOW}   • This is a major system upgrade that may take 1-2 hours${NC}"
        echo -e "${YELLOW}   • Ensure you have recent backups of important data${NC}"
        echo -e "${YELLOW}   • The system will need to be rebooted after upgrade${NC}"
        echo -e "${YELLOW}   • Some services will be temporarily unavailable${NC}"
        echo ""
        
        # Prompt user for distribution upgrade
        while true; do
            echo -e "${CYAN}Do you want to perform a distribution upgrade to Debian $new_version ($new_codename)?${NC}"
            read -p "Proceed with distribution upgrade? (y/N): " choice
            
            case $choice in
                [Yy]* )
                    log_message "User approved distribution upgrade from $current_codename to $new_codename"
                    echo "$new_codename" # Return the target codename
                    return 0
                    ;;
                [Nn]* | "" )
                    log_message "User declined distribution upgrade"
                    echo -e "${BLUE}Distribution upgrade declined. Continuing with regular updates.${NC}"
                    return 1
                    ;;
                * )
                    echo -e "${RED}Please answer yes (y) or no (n).${NC}"
                    ;;
            esac
        done
    else
        log_message "No distribution upgrade available or unsupported version: $current_codename"
        return 1
    fi
}

# Function to backup critical system information
create_backup_info() {
    local backup_dir="/tmp/debian-upgrade-backup"
    mkdir -p "$backup_dir"
    
    log_message "INFO: Creating backup information..."
    
    # Backup package selections
    dpkg --get-selections '*' > "$backup_dir/package-selections.txt"
    
    # Backup APT sources
    cp -r /etc/apt "$backup_dir/apt-backup" 2>/dev/null
    
    # Backup sources list
    if [ -f /etc/apt/sources.list ]; then
        cp /etc/apt/sources.list "$backup_dir/sources.list.backup"
    fi
    
    # Save current system info
    lsb_release -a > "$backup_dir/system-info.txt" 2>/dev/null
    uname -a >> "$backup_dir/system-info.txt"
    
    log_message "Backup information saved to $backup_dir"
}

# Function to update sources for distribution upgrade
update_sources_for_upgrade() {
    local new_codename="$1"
    local sources_updated=false
    
    log_message "INFO: Updating APT sources for $new_codename..."
    
    # Backup current sources
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.backup-$(date +%Y%m%d) 2>/dev/null
    
    # Check if using new deb822 format
    if ls /etc/apt/sources.list.d/*.sources &>/dev/null; then
        log_message "INFO: Detected deb822 format sources"
        
        # Update deb822 format files
        for sources_file in /etc/apt/sources.list.d/*.sources; do
            if [ -f "$sources_file" ]; then
                sudo cp "$sources_file" "$sources_file.backup-$(date +%Y%m%d)"
                # Update suites in deb822 format
                sudo sed -i -E "s/^(Suites:.*)(bookworm|bullseye)(.*)$/\1$new_codename\3/" "$sources_file"
                sources_updated=true
            fi
        done
    fi
    
    # Update traditional sources.list format
    if [ -f /etc/apt/sources.list ]; then
        sudo sed -i -E "s/^(deb.*)(bookworm|bullseye)(.*)$/\1$new_codename\3/" /etc/apt/sources.list
        sources_updated=true
    fi
    
    # Update sources.list.d/*.list files
    for list_file in /etc/apt/sources.list.d/*.list; do
        if [ -f "$list_file" ]; then
            sudo cp "$list_file" "$list_file.backup-$(date +%Y%m%d)"
            sudo sed -i -E "s/^(deb.*)(bookworm|bullseye)(.*)$/\1$new_codename\3/" "$list_file"
            sources_updated=true
        fi
    done
    
    if $sources_updated; then
        log_message "APT sources updated for $new_codename"
        return 0
    else
        log_message "ERROR: Could not update APT sources"
        return 1
    fi
}

# Function to perform distribution upgrade
perform_distribution_upgrade() {
    local new_codename="$1"
    
    echo ""
    echo -e "${CYAN}Starting distribution upgrade to $new_codename...${NC}"
    
    # Update sources
    if ! update_sources_for_upgrade "$new_codename"; then
        log_message "ERROR: Failed to update APT sources"
        return 1
    fi
    
    # Update package lists
    echo -e "${BLUE}Updating package lists...${NC}"
    if ! sudo apt update; then
        log_message "ERROR: Failed to update package lists for $new_codename"
        return 1
    fi
    
    # Check upgrade space requirements
    echo -e "${BLUE}Checking upgrade space requirements...${NC}"
    sudo apt -o APT::Get::Trivial-Only=true full-upgrade 2>/dev/null | grep -E "^(Need to get|After this operation)" || true
    
    # Minimal upgrade first (official Debian procedure)
    echo -e "${BLUE}Performing minimal system upgrade...${NC}"
    if ! sudo apt upgrade --without-new-pkgs -y; then
        log_message "ERROR: Minimal upgrade failed"
        return 1
    fi
    
    # Full upgrade
    echo -e "${BLUE}Performing full system upgrade...${NC}"
    if ! sudo apt full-upgrade -y; then
        log_message "ERROR: Full upgrade failed"
        
        # Try with immediate configure disabled
        echo -e "${YELLOW}Retrying with APT::Immediate-Configure=0...${NC}"
        if ! sudo apt full-upgrade -y -o APT::Immediate-Configure=0; then
            log_message "ERROR: Full upgrade failed even with immediate configure disabled"
            return 1
        fi
    fi
    
    # Clean up
    echo -e "${BLUE}Cleaning up unnecessary packages...${NC}"
    sudo apt autoremove -y
    sudo apt autoclean
    
    log_message "Distribution upgrade to $new_codename completed successfully"
    
    # Offer reboot
    echo ""
    echo -e "${GREEN}Distribution upgrade completed successfully!${NC}"
    echo -e "${YELLOW}A system reboot is required to complete the upgrade.${NC}"
    
    while true; do
        read -p "Do you want to reboot now? (y/N): " reboot_choice
        case $reboot_choice in
            [Yy]* )
                log_message "System reboot initiated after distribution upgrade"
                echo -e "${BLUE}Rebooting system...${NC}"
                sudo reboot
                ;;
            [Nn]* | "" )
                echo -e "${YELLOW}Please remember to reboot your system when convenient.${NC}"
                echo -e "${BLUE}The upgrade may not be fully effective until reboot.${NC}"
                break
                ;;
            * )
                echo -e "${RED}Please answer yes (y) or no (n).${NC}"
                ;;
        esac
    done
    
    return 0
}

# Function to perform regular system updates
perform_regular_updates() {
    echo -e "${BLUE}Performing regular system updates...${NC}"
    
    # Update package lists
    echo "Updating package lists..."
    if ! sudo apt update; then
        log_message "Failed to update package lists"
        send_notification "Failed to update package lists. Check the log at $LOGFILE for details."
        return 1
    fi
    log_message "Package lists updated successfully"
    
    # Upgrade installed packages
    echo "Upgrading installed packages..."
    if ! sudo apt upgrade -y; then
        log_message "Failed to upgrade installed packages"
        send_notification "Failed to upgrade installed packages. Check the log at $LOGFILE for details."
        return 1
    fi
    log_message "Installed packages upgraded successfully"
    
    # Check and update Flatpak packages
    if command -v flatpak &>/dev/null && flatpak list &>/dev/null; then
        echo "Updating Flatpak packages..."
        if sudo flatpak update -y &>/tmp/flatpak_update.log; then
            log_message "Flatpak packages updated successfully"
        else
            log_message "Failed to update Flatpak packages"
            send_notification "Failed to update Flatpak packages. Check the log at $LOGFILE for details."
        fi
    else
        log_message "No Flatpak packages installed. Skipping Flatpak update."
    fi
    
    # Install updated kernel
    echo "Installing updated kernel..."
    if ! sudo apt install linux-image-amd64 -y; then
        log_message "Failed to install updated kernel"
        send_notification "Failed to install updated kernel. Check the log at $LOGFILE for details."
    else
        log_message "Updated kernel installed successfully"
    fi
    
    # Clean up unnecessary packages
    echo "Removing unnecessary packages..."
    if ! sudo apt autoremove -y; then
        log_message "Failed to remove unnecessary packages"
        send_notification "Failed to remove unnecessary packages. Check the log at $LOGFILE for details."
    else
        log_message "Unnecessary packages removed successfully"
    fi
    
    return 0
}

# Main script execution
main() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              Debian System Update & Upgrade Tool            ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log_message "Starting Debian system update process"
    
    # Verify system state
    if ! verify_system_state; then
        log_message "ERROR: System state verification failed"
        echo -e "${RED}Please fix system issues before proceeding with upgrade.${NC}"
        exit 1
    fi
    
    # Check disk space
    if ! check_disk_space; then
        echo -e "${YELLOW}Continue anyway? (y/N): ${NC}"
        read -r continue_choice
        if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
            log_message "Upgrade cancelled due to insufficient disk space"
            exit 1
        fi
    fi
    
    # Create backup information
    create_backup_info
    
    # Check for distribution upgrades
    if new_codename=$(check_distribution_upgrade); then
        # Perform distribution upgrade
        if perform_distribution_upgrade "$new_codename"; then
            log_message "Distribution upgrade process completed successfully"
            send_notification "Debian distribution upgrade completed successfully!"
            exit 0
        else
            log_message "ERROR: Distribution upgrade failed"
            echo -e "${RED}Distribution upgrade failed. Check logs for details.${NC}"
            echo -e "${YELLOW}Falling back to regular updates...${NC}"
        fi
    fi
    
    # Perform regular updates
    if perform_regular_updates; then
        log_message "Regular update process completed successfully"
        echo -e "${GREEN}System update completed successfully!${NC}"
        echo "Check the log at $LOGFILE for details."
        send_notification "Debian system update completed successfully!"
    else
        log_message "ERROR: Regular update process failed"
        echo -e "${RED}System update failed. Check logs for details.${NC}"
        exit 1
    fi
}

# Run main function
main "$@"