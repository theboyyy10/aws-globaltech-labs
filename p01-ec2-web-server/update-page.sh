#!/bin/bash
# update-page.sh
# Rebuilds /var/www/html/index.html for Globaltech using IMDSv2 metadata.
# Usage: sudo ./update-page.sh

# Stop on undefined variables and on failures inside pipelines.
set -uo pipefail

# Location of the web page and the IMDS base URL used throughout the script.
WEB_FILE="/var/www/html/index.html"
IMDS="http://169.254.169.254/latest"

# Make sure the script is run as root (needed to write into /var/www/html).
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script with sudo: sudo $0" >&2
    exit 1
fi

# Request an IMDSv2 session token (valid for 60 seconds) with a PUT request.
TOKEN=$(curl -s -f --max-time 5 -X PUT "${IMDS}/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60")

# Abort if no token was returned, since every later call depends on it.
if [ -z "${TOKEN}" ]; then
    echo "Could not get an IMDSv2 token. Is this an EC2 instance?" >&2
    exit 1
fi

# Helper function: fetch one metadata path using the token.
# Prints "N/A" if the value does not exist (e.g. no public IP assigned).
get_meta() {
    local value
    value=$(curl -s -f --max-time 5 \
        -H "X-aws-ec2-metadata-token: ${TOKEN}" \
        "${IMDS}/meta-data/$1")
    echo "${value:-N/A}"
}

# Read the five metadata values that will be shown in the table.
INSTANCE_ID=$(get_meta "instance-id")
INSTANCE_TYPE=$(get_meta "instance-type")
REGION=$(get_meta "placement/region")
AZ=$(get_meta "placement/availability-zone")
PUBLIC_IP=$(get_meta "public-ipv4")

# Capture the date and time of this update for the page footer.
UPDATED_AT=$(date '+%Y-%m-%d %H:%M:%S %Z')

# Build the new page in a temporary file first, so a failure never leaves
# a half-written index.html behind.
TMP_FILE=$(mktemp)

# Write the HTML: heading, welcome paragraph, metadata table and update time.
cat > "${TMP_FILE}" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Globaltech</title>
  <style>
    body { font-family: Arial, sans-serif; max-width: 700px; margin: 40px auto; padding: 0 16px; color: #222; }
    h1 { color: #0b5394; }
    table { border-collapse: collapse; width: 100%; margin-top: 20px; }
    th, td { border: 1px solid #ccc; padding: 8px 12px; text-align: left; }
    th { background: #f2f2f2; width: 40%; }
    footer { margin-top: 30px; font-size: 0.85em; color: #666; }
  </style>
</head>
<body>
  <h1>Welcome to Globaltech</h1>
  <p>Globaltech delivers reliable, innovative technology solutions to customers around the world. This page is served from an Amazon EC2 instance, and the details below describe the server you are connected to.</p>

  <table>
    <tr><th>Instance ID</th><td>${INSTANCE_ID}</td></tr>
    <tr><th>Instance Type</th><td>${INSTANCE_TYPE}</td></tr>
    <tr><th>Region</th><td>${REGION}</td></tr>
    <tr><th>Availability Zone</th><td>${AZ}</td></tr>
    <tr><th>Public IPv4</th><td>${PUBLIC_IP}</td></tr>
  </table>

  <footer>Page last updated: ${UPDATED_AT}</footer>
</body>
</html>
EOF

# Move the finished page into place and set permissions Apache can read.
mv "${TMP_FILE}" "${WEB_FILE}"
chmod 644 "${WEB_FILE}"

# Confirm success to the person running the script.
echo "Updated ${WEB_FILE} at ${UPDATED_AT}"
