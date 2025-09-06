#!/bin/bash

# Define the script path
SCRIPT_PATH="$( cd "$( dirname ""${BASH_SOURCE[0]}" )" && pwd )"

# Function to check disk usage and trigger refresh
check_disk_usage() {
    local usage=$(df "$SCRIPT_PATH" | grep / | awk '{ print $5 }' | sed 's/%//g')
    if [ "$usage" -ge 95 ]; then
        echo "Disk usage is at ${usage}%, triggering refresh..."
        # Trigger refresh logic here
    else
        echo "Disk usage is at ${usage}%, no action needed."
    fi
}

# Main loop to monitor disk usage
while true; do
    check_disk_usage
    sleep 60  # Check every 60 seconds
done
