# Tunnelblick Installation & Configuration Script for MDM Deployment
This script automates the installation of [Tunnelblick](https://tunnelblick.net/), a leading OpenVPN client for macOS, and optionally installs a provided OpenVPN configuration file. It is designed for deployment via Mobile Device Management (MDM) solutions, with the script provided focused on Addigy, but can be adapted for other MDM platforms with minor modifications.

## Features
- Automated Download & Install: Fetches the latest stable Tunnelblick DMG, mounts, and installs the app silently.
- MDM-Friendly: Designed for use in MDM deployment workflows (e.g., Addigy, Jamf, Kandji, Mosyle). The script uses root privileges and avoids user interaction.
- Permissions & Security: Sets correct permissions on the Tunnelblick app and shared directories. Performs post-install security steps to prevent admin popups on first launch. So app can be used straight away for standard users
- OpenVPN Configuration (Optional): If a .ovpn file is present, it packages and installs it as a Tunnelblick configuration using the command line, with system-wide preferences to keep the VPN connected during sleep and to stop automatic reconnections.
 
## Usage
1. Prepare the Script:
   - Place your OpenVPN configuration file (e.g., myvpn.ovpn) in the same directory as the script or package it with your MDM deployment.
   - Edit the script to set CONFIG_NAME and CONFIG_FILE to match your configuration.
  
2. MDM Deployment:
   - Upload the script (and your .ovpn file, if used) to your MDM platform.
   
3. Script Execution:
   - The script must run as root (which is standard for MDM scripts).
   - No user interaction is requiredß.
  
## Customization
- CONFIG_NAME: Set this to a name for your VPN configuration (no spaces recommended).
- CONFIG_FILE: Set this to the filename of your .ovpn file.
- TEMP_TBLK Path: If not using Addigy, change the TEMP_TBLK variable to a suitable writable path for your MDM.

## Notes
- If no .ovpn file is found, the script will skip the configuration installation step and just install TunnelBlick.
- The script sets system preferences to keep the VPN connected during sleep/user switching for all configurations and sets system preferences to stop automatic reconnections on wake if the VPN has been disconnected.
- The final security steps ensure Tunnelblick launches without an admin authentication prompt.