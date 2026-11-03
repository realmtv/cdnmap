#!/bin/bash

if [ -f "/app/.env" ]; then
    export $(cat /app/.env | xargs)
elif [ -f ".env" ]; then
    export $(cat .env | xargs)
fi

MIKROTIK_IP=${MIKROTIK_IP:-192.168.88.1}
MIKROTIK_USER=${MIKROTIK_USER:-admin}
ITERATIONS=${ITERATIONS:-20}
DELAY=${DELAY:-5}
RUN_INTERVAL=${RUN_INTERVAL:-21600}

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
    sys.exit(1)
" | while IFS='|' read -r mode target list_name; do

        if [ -z "$mode" ] || [ -z "$target" ] || [ -z "$list_name" ]; then
            continue
        fi

        if [ "$mode" == "crawl" ]; then
            python3 cdnmap.py "$target" -i "$ITERATIONS" -d "$DELAY" -m "$list_name" -o commands.txt > /dev/null 2>&1
        elif [ "$mode" == "dns_only" ]; then
            python3 cdnmap.py -i "$ITERATIONS" -d "$DELAY" -m "$list_name" --list "$target" -o commands.txt > /dev/null 2>&1
        fi

        if [ -f "commands.txt" ]; then
            (echo "/ip firewall address-list remove [find where dynamic=yes]"; cat commands.txt; echo "") > commands_fixed.txt
            
            cp /root/.ssh/id_rsa /tmp/id_rsa_fixed 2>/dev/null
            chmod 600 /tmp/id_rsa_fixed 2>/dev/null
            
            ssh -n -q -o StrictHostKeyChecking=no \
                -o KexAlgorithms=+diffie-hellman-group14-sha256,diffie-hellman-group-exchange-sha256 \
                -o HostKeyAlgorithms=+ssh-rsa \
                -i /tmp/id_rsa_fixed "${MIKROTIK_USER}@${MIKROTIK_IP}" < commands_fixed.txt
            
            rm -f commands.txt commands_fixed.txt /tmp/id_rsa_fixed 2>/dev/null
        fi
    done

    sleep "$RUN_INTERVAL"
done