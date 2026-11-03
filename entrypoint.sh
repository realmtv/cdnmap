#!/bin/bash

ITERATIONS=${ITERATIONS:-20}
DELAY=${DELAY:-5}
RUN_INTERVAL=${RUN_INTERVAL:-86400}

# CRITICAL FIX: Source environment variables if running inside container path
if [ -f "/app/.env" ]; then
    export $(cat /app/.env | xargs)
elif [ -f ".env" ]; then
    export $(cat .env | xargs)
fi

echo "[+] Starting cdnmap production daemon..."

while true; do
    python3 -c "
import json, sys
try:
    with open('/app/targets.json') as f:
        data = json.load(f)
    for key, val in data.items():
        if key.startswith('_'):
            continue
        if isinstance(val, dict) and val.get('enabled') is True:
            print(f\"{val['mode']}|{val['target']}|{val['address_list']}\")
except Exception as e:
    print(f'[-] Error reading config: {e}', file=sys.stderr)
    sys.exit(1)
" | while IFS='|' read -r mode target list_name; do
        echo "[+] Processing $list_name ($target) in mode $mode..."
        
        if [ "$mode" == "crawl" ]; then
            python3 cdnmap.py "$target" -i "$ITERATIONS" -d "$DELAY" -m "$list_name" -o commands.txt
        elif [ "$mode" == "dns_only" ]; then
            python3 cdnmap.py --list "$target" -i "$ITERATIONS" -d "$DELAY" -m "$list_name" -o commands.txt
        else
            echo "[-] Unknown mode: $mode for target $target. Skipping."
            continue
        fi
        
        if [ -f "commands.txt" ]; then
            echo "[+] Script generated successfully. Deploying to MikroTik..."
            
            if [ -f "/root/.ssh/id_rsa" ] && [ ! -z "${MIKROTIK_IP}" ] && [ ! -z "${MIKROTIK_USER}" ]; then
                ssh -n -q -T -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa "${MIKROTIK_USER}@${MIKROTIK_IP}" "$(cat commands.txt)"
            else
                echo "[-] WARNING: SSH key or credentials missing. Manual deployment required."
            fi
            
            rm commands.txt
        else
            echo "[-] Error: Failed to generate MikroTik commands for $target."
        fi
    done
    
    echo "[+] All targets processed. Sleeping for $RUN_INTERVAL seconds..."
    sleep "$RUN_INTERVAL"
done