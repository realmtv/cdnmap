#!/bin/bash

if [ -f "/app/.env" ]; then
    export $(cat /app/.env | xargs)
elif [ -f ".env" ]; then
    export $(cat .env | xargs)
fi

export M_IP=${MIKROTIK_IP:-192.168.88.1}
export M_USER=${MIKROTIK_USER:-admin}
export ITERATIONS=${ITERATIONS:-20}
export DELAY=${DELAY:-5}
export RUN_INTERVAL=${RUN_INTERVAL:-21600}

while true; do
    python3 -u -c "
import json, os, subprocess, sys
try:
    with open('/app/targets.json') as f:
        data = json.load(f)
    for key, val in data.items():
        if key.startswith('_') or not isinstance(val, dict) or not val.get('enabled'):
            continue
        
        mode = val.get('mode')
        target = val.get('target')
        list_name = val.get('address_list')
        
        if not mode or not target or not list_name:
            continue
            
        print(f'[+] Syncing address list: {list_name}', flush=True)
        
        iterations = os.environ.get('ITERATIONS', '20')
        delay = os.environ.get('DELAY', '5')
        
        cmd = ['python3', 'cdnmap.py', '-i', iterations, '-d', delay, '-m', list_name, '-o', '/app/commands.txt']
        if mode == 'crawl':
            cmd.append(target)
        elif mode == 'dns_only':
            cmd.extend(['--list', target])
            
        subprocess.run(cmd)
        
        mikrotik_commands = f'/ip firewall address-list remove [find where list=\"{list_name}\"]'
        
        if os.path.exists('/app/commands.txt'):
            with open('/app/commands.txt', 'r') as cf:
                payload = cf.read()
            
            clean_payload = payload.replace('\r', '').strip()
            if clean_payload:
                mikrotik_commands += '\n' + clean_payload
            else:
                print(f'[-] cdnmap.py returned 0 hosts for {list_name}. List will be cleared.', flush=True)
        
        os.system('cp /root/.ssh/id_rsa /tmp/id_rsa_fixed 2>/dev/null && chmod 600 /tmp/id_rsa_fixed 2>/dev/null')
        
        ssh_cmd = [
            'ssh', '-T', '-q', '-o', 'StrictHostKeyChecking=no',
            '-o', 'UserKnownHostsFile=/dev/null',
            '-o', 'KexAlgorithms=+diffie-hellman-group14-sha256,diffie-hellman-group-exchange-sha256',
            '-o', 'HostKeyAlgorithms=+ssh-rsa',
            '-i', '/tmp/id_rsa_fixed', f'{os.environ[\"M_USER\"]}@{os.environ[\"M_IP\"]}',
            mikrotik_commands
        ]
        
        print(f'[*] Uploading to MikroTik...', flush=True)
        subprocess.run(ssh_cmd)
        
        if os.path.exists('/app/commands.txt'):
            os.remove('/app/commands.txt')
        os.system('rm -f /tmp/id_rsa_fixed 2>/dev/null')
        print(f'[+] Done for {list_name}\n', flush=True)
except Exception as e:
    print(f'[-] Error: {e}', file=sys.stderr, flush=True)
"
    echo "[*] Sleeping for $RUN_INTERVAL seconds..."
    sleep "$RUN_INTERVAL"
done