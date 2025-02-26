#!/bin/bash
#
# Script to update a custom SSL certificate on a UNVR.
# This script downloads the certificate and private key from Cert Warden via its API,
# compares them with the current files in /data/unifi-core/config, and if they differ:
#   - Backs up the existing files (with a date stamp)
#   - Replaces them with the new certificate and key.
#   - Restarts the unifi-core service to apply the new certificate.
#
# Note: On newer UniFi OS devices, the custom cert files are stored in:
#   /data/unifi-core/config/unifi-core.crt   (the certificate, including intermediate certs)
#   /data/unifi-core/config/unifi-core.key   (the private key)
#
# Customize the following variables for your environment:

# API credentials and endpoint details for Cert Warden:
cert_apikey="<YOUR_CERT_API_KEY>"
key_apikey="<YOUR_KEY_API_KEY>"
server="certwarden.example.com"  # Your Cert Warden server hostname (and port if needed)
cert_name="unifi.example.com"      # The certificate identifier in Cert Warden

# API paths (adjust if your Cert Warden instance uses different paths)
api_cert_path="certwarden/api/v1/download/certificates/$cert_name"
api_key_path="certwarden/api/v1/download/privatekeys/$cert_name"

# Destination paths on the UNVR:
dest_cert="/data/unifi-core/config/unifi-core.crt"
dest_key="/data/unifi-core/config/unifi-core.key"

# Temporary directory for downloads:
temp_dir="/tmp/cw_unifi"
mkdir -p "$temp_dir"

# --- Download the certificate ---
echo "Downloading certificate from Cert Warden..."
http_status_cert=$(curl -L "https://$server/$api_cert_path" \
    -H "apiKey: $cert_apikey" \
    --output "$temp_dir/unifi-core.crt" \
    --write-out "%{http_code}")
if [ "$http_status_cert" -ne 200 ]; then
    echo "Error: Failed to download certificate (HTTP status $http_status_cert)."
    exit 1
fi

# --- Download the private key ---
echo "Downloading private key from Cert Warden..."
http_status_key=$(curl -L "https://$server/$api_key_path" \
    -H "apiKey: $key_apikey" \
    --output "$temp_dir/unifi-core.key" \
    --write-out "%{http_code}")
if [ "$http_status_key" -ne 200 ]; then
    echo "Error: Failed to download private key (HTTP status $http_status_key)."
    exit 1
fi

# --- Check if an update is needed ---
update_needed=0
if [ -f "$dest_cert" ]; then
    cmp -s "$temp_dir/unifi-core.crt" "$dest_cert" || update_needed=1
else
    update_needed=1
fi

if [ -f "$dest_key" ]; then
    cmp -s "$temp_dir/unifi-core.key" "$dest_key" || update_needed=1
else
    update_needed=1
fi

if [ $update_needed -eq 0 ]; then
    echo "Certificate and key are already up-to-date. Exiting."
    rm -rf "$temp_dir"
    exit 0
fi

# --- Backup existing files ---
backup_date=$(date +'%Y%m%d')
if [ -f "$dest_cert" ]; then
    cp "$dest_cert" "${dest_cert}.${backup_date}"
    echo "Backed up current certificate to ${dest_cert}.${backup_date}"
fi
if [ -f "$dest_key" ]; then
    cp "$dest_key" "${dest_key}.${backup_date}"
    echo "Backed up current key to ${dest_key}.${backup_date}"
fi

# (Optional) Remove backups older than 365 days:
backup_dir="/data/unifi-core/config"
find "$backup_dir" -maxdepth 1 -name "unifi-core.crt.*" -mtime +365 -exec rm {} \;
find "$backup_dir" -maxdepth 1 -name "unifi-core.key.*" -mtime +365 -exec rm {} \;
echo "Old backups removed."

# --- Install new certificate and key ---
cp "$temp_dir/unifi-core.crt" "$dest_cert" || { echo "Failed to install new certificate."; exit 1; }
cp "$temp_dir/unifi-core.key" "$dest_key" || { echo "Failed to install new key."; exit 1; }
chmod 600 "$dest_cert" "$dest_key"
echo "Installed new certificate and key."

# Clean up temporary files
rm -rf "$temp_dir"

# --- Restart unifi-core service ---
echo "Restarting unifi-core service to apply the new certificate..."
systemctl restart unifi-core || { echo "Error: Unable to restart unifi-core service."; exit 1; }
echo "UNVR certificate update complete."

exit 0
