#!/bin/bash
# Unraid Userscript to update the SSL certificate bundle for Unraid.
# This script builds a single file (bundle) by concatenating the certificate chain
# and the private key, which is what Unraid expects.j
#
# Prerequisite:
#  - Cert Warden Client must be running via Docker on Unraid.
#
# Source files (from Cert Warden Client):
#   - Certificate chain: /mnt/user/appdata/certwarden-client/<YOUR_SERVER_NAME>/certchain.pem
#   - Private key:      /mnt/user/appdata/certwarden-client/<YOUR_SERVER_NAME>/key.pem
#
# Destination file (bundle):
#   - /boot/config/ssl/certs/<YOUR_SERVER_NAME>_unraid_bundle.pem
#
# The bundle file will contain the certificate chain followed by the private key.
# After updating, the script backs up the old bundle, removes backups older than 1 year,
# and restarts Nginx to apply the changes.

set -e

# Define source file paths
CERT_SOURCE="/mnt/user/appdata/certwarden-client/<YOUR_SERVER_NAME>/certchain.pem"
KEY_SOURCE="/mnt/user/appdata/certwarden-client/<YOUR_SERVER_NAME>/key.pem"

# Define destination bundle file path
DEST_BUNDLE="/boot/config/ssl/certs/<YOUR_SERVER_NAME>_unraid_bundle.pem"

# Ensure source files exist
if [ ! -f "$CERT_SOURCE" ]; then
    echo "Error: Certificate chain file not found at $CERT_SOURCE."
    exit 1
fi

if [ ! -f "$KEY_SOURCE" ]; then
    echo "Error: Private key file not found at $KEY_SOURCE."
    exit 1
fi

# If destination bundle exists, check modification times.
if [ -f "$DEST_BUNDLE" ]; then
    if [ "$CERT_SOURCE" -ot "$DEST_BUNDLE" ] && [ "$KEY_SOURCE" -ot "$DEST_BUNDLE" ]; then
        echo "Destination bundle is up-to-date. No changes made."
        exit 0
    fi
fi

# Backup existing destination bundle if it exists
backup_date=$(date +'%Y%m%d')
if [ -f "$DEST_BUNDLE" ]; then
    cp "$DEST_BUNDLE" "${DEST_BUNDLE}.${backup_date}"
    echo "Backed up existing bundle to ${DEST_BUNDLE}.${backup_date}"
fi

# Remove backups older than 365 days in the destination directory
backup_dir="/boot/config/ssl/certs"
find "$backup_dir" -maxdepth 1 -name "<YOUR_SERVER_NAME>_unraid_bundle.pem.*" -mtime +365 -exec rm {} \;
echo "Old backups (older than 1 year) removed."

# Create a temporary file to build the new bundle
TEMP_BUNDLE=$(mktemp)

# Concatenate the certificate chain and the private key into the temporary file.
# (Order: certificate chain first, then private key)
cat "$CERT_SOURCE" "$KEY_SOURCE" > "$TEMP_BUNDLE" || { echo "Failed to create bundle file."; exit 1; }

# Move the temporary bundle to the destination
mv "$TEMP_BUNDLE" "$DEST_BUNDLE" || { echo "Failed to move bundle file to destination."; exit 1; }

# Set secure permissions on the bundle file (readable only by root)
chmod 600 "$DEST_BUNDLE"

echo "Successfully updated SSL bundle file: $DEST_BUNDLE"

# Restart the Nginx web server to apply the new certificate bundle.
echo "Restarting Nginx web server..."
/etc/rc.d/rc.nginx stop || { echo "Failed to stop Nginx."; exit 1; }
sleep 5
/etc/rc.d/rc.nginx start || { echo "Failed to start Nginx."; exit 1; }
echo "SSL certificates successfully reloaded."
