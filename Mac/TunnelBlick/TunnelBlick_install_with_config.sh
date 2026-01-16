#!/bin/bash
set -e  # Exit on any error

# ============================================================================
# TUNNELBLICK MDM INSTALLATION SCRIPT FOR ADDIGY
# ============================================================================
# This script:
# - Downloads and installs Tunnelblick using the correct installer command (259)
# - Installs an OpenVPN configuration as a Shared configuration
# - Sets forced preferences for MDM-managed environments
# - Works for fresh installs AND updates (no admin prompts)
# ============================================================================

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

log "============================================"
log "Starting Tunnelblick installation/update"
log "============================================"

# Determine the working directory (where Addigy downloads files)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
log "Working directory: $SCRIPT_DIR"

# ============================================================================
# CONFIGURATION - UPDATE THESE FOR YOUR INSTALLATION
# ============================================================================
CONFIG_NAME="OpenVPNFile"            # Name for the configuration (no spaces)
CONFIG_FILE="open.ovpn"  # The .ovpn filename in the Addigy package
# ============================================================================

# Stop Tunnelblick if running
log "Stopping Tunnelblick processes"
pkill -f Tunnelblick 2>/dev/null || true
sleep 2

# Download latest stable Tunnelblick from official source
dLoadURL="https://tunnelblick.net/iprelease/Latest_Tunnelblick_Stable.dmg"
pathToDmg="/private/tmp/Tunnelblick.dmg"

# Clean up any previous download
rm -f "$pathToDmg"

log "Downloading Tunnelblick from $dLoadURL"
curl --connect-timeout 300 --max-time 600 --retry 3 -o "$pathToDmg" -L "$dLoadURL"
check_command "Download"

# Verify download
if [ ! -f "$pathToDmg" ]; then
    log "ERROR: Download failed - file not found"
    exit 1
fi

log "Download complete. Removing quarantine attribute..."
xattr -d com.apple.quarantine "$pathToDmg" 2>/dev/null || true

# Unmount any existing Tunnelblick volume
hdiutil detach /Volumes/Tunnelblick 2>/dev/null || true
sleep 1

# Mount DMG
log "Mounting DMG"
hdiutil attach -quiet -nobrowse -mountpoint /Volumes/Tunnelblick "$pathToDmg"
check_command "Mount DMG"

# Verify mount and installer exists
if [ ! -f "/Volumes/Tunnelblick/Tunnelblick.app/Contents/Resources/installer" ]; then
    log "ERROR: Installer not found in mounted DMG"
    hdiutil detach /Volumes/Tunnelblick 2>/dev/null || true
    rm -f "$pathToDmg"
    exit 1
fi

# Wait for mount to be fully ready
sleep 3

# ============================================================================
# INSTALL TUNNELBLICK USING CORRECT COMMAND (259)
# Per documentation: https://tunnelblick.net/cInstallFromCommandLine.html
# "installer 259" copies to /Applications, secures it, installs daemon,
# and makes it ready for any user (standard or admin) without prompts.
# This command also works for UPDATES - it will move old version to Trash.
# ============================================================================

log "Installing Tunnelblick using 'installer 259' (full install with daemon and security)"
/Volumes/Tunnelblick/Tunnelblick.app/Contents/Resources/installer 259
INSTALL_EXIT=$?

if [ $INSTALL_EXIT -ne 0 ]; then
    log "ERROR: Tunnelblick installation failed with exit code $INSTALL_EXIT"
    hdiutil detach /Volumes/Tunnelblick 2>/dev/null || true
    rm -f "$pathToDmg"
    exit 1
fi

log "Tunnelblick application installed/updated successfully"

# Cleanup DMG
log "Unmounting DMG"
sleep 2
hdiutil detach /Volumes/Tunnelblick 2>/dev/null || true
rm -f "$pathToDmg"

# Verify installation
if [ ! -d "/Applications/Tunnelblick.app" ]; then
    log "ERROR: Tunnelblick app not found after installation"
    exit 1
fi

log "Verified Tunnelblick.app exists in /Applications"

# ============================================================================
# CONFIGURATION INSTALLATION SECTION
# Using installer 0x7000 for Shared configurations (available to all users)
# ============================================================================

# Check for config file in script directory first, then current directory
if [ -f "$SCRIPT_DIR/$CONFIG_FILE" ]; then
    CONFIG_PATH="$SCRIPT_DIR/$CONFIG_FILE"
elif [ -f "./$CONFIG_FILE" ]; then
    CONFIG_PATH="./$CONFIG_FILE"
else
    CONFIG_PATH=""
fi

if [ -z "$CONFIG_PATH" ]; then
    log "WARNING: Configuration file '$CONFIG_FILE' not found in $SCRIPT_DIR"
    log "Skipping configuration installation."
    log "If you want automatic configuration, ensure the .ovpn file is in the Addigy package."
else
    log "Found configuration file: $CONFIG_PATH"
    
    # Create temporary .tblk directory
    TEMP_TBLK="/private/tmp/${CONFIG_NAME}.tblk"
    rm -rf "$TEMP_TBLK"
    mkdir -p "$TEMP_TBLK"
    
    log "Creating Tunnelblick VPN Configuration (.tblk)"
    
    # Copy the OpenVPN configuration file
    cp "$CONFIG_PATH" "$TEMP_TBLK/config.ovpn"
    
    # Set proper permissions on the .tblk
    chmod 755 "$TEMP_TBLK"
    chmod 644 "$TEMP_TBLK/config.ovpn"
    
    # Install as Shared configuration using 0x7000
    log "Installing shared configuration using 'installer 0x7000'"
    /Applications/Tunnelblick.app/Contents/Resources/installer 0x7000 "$TEMP_TBLK"
    CONFIG_EXIT=$?
    
    if [ $CONFIG_EXIT -eq 0 ]; then
        log "Configuration '$CONFIG_NAME' installed successfully as Shared configuration"
    else
        log "WARNING: Configuration installation returned exit code $CONFIG_EXIT"
        log "Configuration may need manual installation or already exists"
    fi
    
    # Clean up temporary .tblk
    rm -rf "$TEMP_TBLK"
    log "Cleaned up temporary .tblk file"
fi

# ============================================================================
# FORCED PREFERENCES
# Location: /Library/Application Support/Tunnelblick/forced-preferences.plist
# Must be owned by root:wheel with permissions 0644
# These override user preferences and cannot be changed by standard users
# Reference: https://tunnelblick.net/cPreferences.html
# ============================================================================

log "Setting up forced preferences"

FORCED_PREFS_DIR="/Library/Application Support/Tunnelblick"
FORCED_PREFS_FILE="$FORCED_PREFS_DIR/forced-preferences.plist"

# Create directory if it doesn't exist
mkdir -p "$FORCED_PREFS_DIR"

# Create forced preferences plist
cat > "$FORCED_PREFS_FILE" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- ============================================ -->
    <!-- COMPUTER SLEEP/WAKE (FORCED - User cannot change) -->
    <!-- Both UNCHECKED = VPN stays connected during sleep -->
    <!-- ============================================ -->
    
    <!-- Disconnect when computer goes to sleep (UNCHECKED) -->
    <!-- doNotDisconnectOnSleep = true means it will NOT disconnect -->
    <key>*-doNotDisconnectOnSleep</key>
    <true/>
    
    <!-- Reconnect when computer wakes up (UNCHECKED/greyed out) -->
    <key>*-doNotReconnectOnWakeFromSleep</key>
    <true/>
    
    <!-- ============================================ -->
    <!-- UPDATE CONTROL (All greyed out - MDM manages updates) -->
    <!-- ============================================ -->
    
    <!-- Check for updates automatically (UNCHECKED and greyed out) -->
    <key>updateCheckAutomatically</key>
    <false/>
    
    <!-- Check only when connected to a VPN (UNCHECKED and greyed out) -->
    <key>TBUpdaterCheckOnlyWhenConnectedToVPN</key>
    <false/>
    
    <!-- Download updates when found (UNCHECKED and greyed out) -->
    <key>TBUpdaterDownloadUpdateWhenAvailable</key>
    <false/>
    
</dict>
</plist>
EOF

# Set correct ownership and permissions for forced preferences
chown root:wheel "$FORCED_PREFS_FILE"
chmod 644 "$FORCED_PREFS_FILE"

log "Forced preferences file created at: $FORCED_PREFS_FILE"

# ============================================================================
# VERIFY FINAL STATE
# ============================================================================

log "Performing final verification..."

# Get installed version
if [ -f "/Applications/Tunnelblick.app/Contents/Info.plist" ]; then
    TB_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "/Applications/Tunnelblick.app/Contents/Info.plist" 2>/dev/null || echo "Unknown")
    log "Installed Tunnelblick version: $TB_VERSION"
fi

# Check for the Tunnelblick helper daemon
if launchctl print system/net.tunnelblick.tunnelblick.tunnelblickd &>/dev/null 2>&1; then
    log "Tunnelblick daemon (tunnelblickd) is registered"
else
    log "NOTE: Tunnelblick daemon will register on first launch"
fi

# List installed shared configurations
SHARED_CONFIGS="/Library/Application Support/Tunnelblick/Shared"
if [ -d "$SHARED_CONFIGS" ]; then
    log "Shared configurations installed:"
    ls -1 "$SHARED_CONFIGS" 2>/dev/null | while read config; do
        log "  - $config"
    done
else
    log "No shared configurations directory found (will be created on first use)"
fi

# Verify forced preferences
if [ -f "$FORCED_PREFS_FILE" ]; then
    log "Forced preferences file exists with correct permissions:"
    ls -la "$FORCED_PREFS_FILE"
fi

log "============================================"
log "INSTALLATION COMPLETE"
log "============================================"
log ""
log "Summary:"
log "  - Tunnelblick installed to /Applications/Tunnelblick.app"
log "  - Used 'installer 259' for proper security setup"
log "  - Forced preferences configured"
log "  - Standard users should NOT see admin prompts on launch"
log ""
log "Settings applied via forced preferences:"
log "  - Disconnect on sleep: UNCHECKED and greyed out"
log "  - Reconnect on wake: UNCHECKED and greyed out"  
log "  - Check for updates automatically: DISABLED and greyed out"
log "  - Check only when connected to VPN: DISABLED and greyed out"
log "  - Download updates when found: DISABLED and greyed out"
log "  - All other settings: User configurable"
log ""
log "============================================"

# ============================================================================
# LAUNCH TUNNELBLICK FOR CURRENT USER
# ============================================================================

# Get the currently logged in user (not root)
CURRENT_USER=$(stat -f "%Su" /dev/console)

if [ "$CURRENT_USER" != "root" ] && [ -n "$CURRENT_USER" ]; then
    log "Launching Tunnelblick for user: $CURRENT_USER"
    sudo -u "$CURRENT_USER" open /Applications/Tunnelblick.app
else
    log "No user logged in at console, skipping launch"
fi

exit 0
