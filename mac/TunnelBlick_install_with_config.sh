#!/bin/bash
set -e  # Exit on any error

# Function to log with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1"
}

# Function to check if command succeeded
check_command() {
    if [ $? -ne 0 ]; then
        log "ERROR: $1 failed"
        exit 1
    fi
}

log "Starting Tunnelblick installation"

# Stop Tunnelblick if running
log "Stopping Tunnelblick processes"
pkill -f Tunnelblick || true

# Download latest stable Tunnelblick from official source
dLoadURL="https://tunnelblick.net/iprelease/Latest_Tunnelblick_Stable.dmg"
pathToDmg="/private/tmp/Tunnelblick.dmg"

log "Downloading Tunnelblick from $dLoadURL"
curl --connect-timeout 300 --max-time 600 --retry 3 -o "$pathToDmg" -L "$dLoadURL"
check_command "Download"

# Verify download
if [ ! -f "$pathToDmg" ]; then
    log "ERROR: Download failed - file not found"
    exit 1
fi

log "Removing quarantine attribute"
xattr -d com.apple.quarantine "$pathToDmg" 2>/dev/null || true

# Mount DMG
log "Mounting DMG"
hdiutil attach -quiet -mountpoint /Volumes/Tunnelblick "$pathToDmg"
check_command "Mount DMG"

# Verify mount
if [ ! -d "/Volumes/Tunnelblick" ]; then
    log "ERROR: DMG mount failed"
    exit 1
fi

# Wait for mount to be ready
sleep 5

# Create required directory
log "Creating Tunnelblick support directory"
mkdir -p "/var/root/Library/Application Support/Tunnelblick"

# Install Tunnelblick
log "Installing Tunnelblick"
if [ -f "/Volumes/Tunnelblick/Tunnelblick.app/Contents/Resources/installer" ]; then
    /Volumes/Tunnelblick/Tunnelblick.app/Contents/Resources/installer 2
    check_command "Tunnelblick installation"
else
    log "ERROR: Installer not found in mounted DMG"
    hdiutil unmount /Volumes/Tunnelblick 2>/dev/null || true
    exit 1
fi

# Cleanup DMG
log "Unmounting DMG"
sleep 3
hdiutil unmount /Volumes/Tunnelblick
check_command "Unmount DMG"

log "Removing temporary files"
rm -f "$pathToDmg"

# Verify installation
if [ ! -d "/Applications/Tunnelblick.app" ]; then
    log "ERROR: Tunnelblick app not found after installation"
    exit 1
fi

log "Tunnelblick installation completed successfully"

log "Allowing system to settle before security configuration..."
sleep 5

# Get current user for configuration
CURRENT_USER=$(/usr/bin/stat -f "%Su" /dev/console 2>/dev/null)
CURRENT_UID=$(/usr/bin/stat -f "%u" /dev/console 2>/dev/null)

log "Current console user: $CURRENT_USER (UID: $CURRENT_UID)"

# Set application permissions
log "Setting application permissions"
chown -R root:admin /Applications/Tunnelblick.app
chmod -R 755 /Applications/Tunnelblick.app

# Create shared Tunnelblick directories
log "Creating shared Tunnelblick directories"
mkdir -p "/Users/Shared/Tunnelblick"
chmod 755 "/Users/Shared/Tunnelblick"

# ============================================================================
# .OPENVPN CONFIGURATION INSTALLATION SECTION - Using Command Line Installation
# ============================================================================

log "Starting configuration installation using command line method"

# Configuration settings - UPDATE THESE FOR YOUR INSTALLATION
CONFIG_NAME="CONFIGNAME"     # Name for the configuration (no spaces recommended)
CONFIG_FILE="FILENAME.ovpn"  # The filename you packaged with the script 

# Check if configuration file exists in the current directory
if [ ! -f "$CONFIG_FILE" ]; then
    log "WARNING: Configuration file '$CONFIG_FILE' not found. Skipping configuration installation."
    log "Upload your .ovpn file to the Software package if you want automatic configuration."
else
    log "Found configuration file: $CONFIG_FILE"

    # Create a Tunnelblick VPN Configuration (.tblk) package from the OpenVPN file
    # Addigy used for packaging so configuration is placed in a specific directory - /Library/Addigy/ansible/packages/TunnelBlick (OpenVPN) (1.01)
    # Creates a temporary .tblk folder for the configuration in same directory
    TEMP_TBLK="/Library/Addigy/ansible/packages/TunnelBlick (OpenVPN) (1.01)/${CONFIG_NAME}.tblk"
    rm -rf "$TEMP_TBLK"
    mkdir -p "$TEMP_TBLK"
    
    log "Creating Tunnelblick VPN Configuration (.tblk) from OpenVPN file"
    log "Creating temporary .tblk at: $TEMP_TBLK"
    
    # Copy the OpenVPN configuration file directly into the .tblk folder
    cp "$CONFIG_FILE" "$TEMP_TBLK/config.ovpn"

    # Set proper permissions
    chmod 755 "$TEMP_TBLK"
    chmod 644 "$TEMP_TBLK/config.ovpn"
    
    # Use Tunnelblick's command line installer for shared configuration
    # installer 0x7001 = install shared configuration without user interaction
    log "Installing shared configuration using Tunnelblick command line installer (0x7001)"
    /Applications/Tunnelblick.app/Contents/Resources/installer 0x7001 "$TEMP_TBLK"
    
    if [ $? -eq 0 ]; then
            log "Configuration '$CONFIG_NAME' installed successfully using command line method"
            
            # Configure VPN settings to keep connection active during sleep/user switching
            log "Configuring VPN connection settings to prevent disconnection during sleep/user switching"
            
            # Setting some system-wide preferences for ALL configurations using "**" wildcard
            /usr/bin/defaults write "/Library/Preferences/net.tunnelblick.tunnelblick.plist" "**-doNotDisconnectOnSleep" -bool true
            /usr/bin/defaults write "/Library/Preferences/net.tunnelblick.tunnelblick.plist" "**-doNotReconnectOnWakeFromSleep" -bool true
            /usr/bin/defaults write "/Library/Preferences/net.tunnelblick.tunnelblick.plist" "**-doNotDisconnectOnFastUserSwitch" -bool true
            /usr/bin/defaults write "/Library/Preferences/net.tunnelblick.tunnelblick.plist" "**-doNotReconnectOnFastUserSwitch" -bool true
            log "Set system-wide preferences: ALL VPN configurations will try to stay connected during sleep and won't try to reconnect automatically on wake if disconnected"

        else
            log "Command line installation failed, configuration may need manual installation"
        fi
        
        # Clean up temporary .tblk
        rm -rf "$TEMP_TBLK"
        log "Cleaned up temporary .tblk file"
    fi

# ============================================================================
# End of .OPENVPN CONFIGURATION INSTALLATION SECTION
# ============================================================================

log "Tunnelblick installation and configuration install completed successfully"

# ============================================================================
# CRITICAL: Final security setup to prevent admin popup on first launch of Tunnelblick
# Based on form discussion: https://groups.google.com/g/tunnelblick-discuss/c/UYeR7vv_rXM
# This MUST run after everything else is complete
# ============================================================================

log "Performing final security setup to prevent admin authentication popup"

# Allow system to fully settle after installation
sleep 3

# Setup folders and secure Tunnelblick app
log "Running installer 5 (setup folders and secure Tunnelblick app)"
/Applications/Tunnelblick.app/Contents/Resources/installer 5 2>/dev/null || log "Installer 5 completed with warnings"

# Secure configurations 
log "Running installer 16 (secure configurations)"
/Applications/Tunnelblick.app/Contents/Resources/installer 16 2>/dev/null || log "Installer 16 completed with warnings"

log "Final security setup completed - Tunnelblick should now launch without initial admin popup"

exit 0