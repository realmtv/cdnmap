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
    python3 -c "
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
            
        print(f'[+] Syncing: {list_name}')
        
        iterations = os.environ.get('ITERATIONS', '20')
        delay = os.environ.get('DELAY', '5')
        
        cmd = ['python3', 'cdnmap.py', '-i', iterations, '-d', delay, '-m', list_name, '-o', 'commands.txt']
        if mode == 'crawl':
            cmd.insert(2, target)
        elif mode == 'dns_only':
            cmd.extend(['--list', target])
            
        subprocess.run(cmd)
        
        if os.path.exists('commands.txt'):
            with open('commands.txt', 'r') as cf:
                payload = cf.read()
            
            if not payload.strip():
                continue
                
            fixed_payload = '/ip firewall address-list remove [find where dynamic=yes]\n' + payload + '\n'
            with open('commands_fixed.txt', 'w') as ff:
                ff.write(fixed_payload)
                
            os.system('cp /root/.ssh/id_rsa /tmp/id_rsa_fixed 2>/dev/null && chmod 600 /tmp/id_rsa_fixed 2>/dev/null')
            
            ssh_cmd = [
                'ssh', '-n', '-o', 'StrictHostKeyChecking=no',
                '-o', 'KexAlgorithms=+diffie-hellman-group14-sha256,diffie-hellman-group-exchange-sha256',
                '-o', 'HostKeyAlgorithms=+ssh-rsa',
                '-i', '/tmp/id_rsa_fixed', f'{os.environ[\"M_USER\"]}@{os.environ[\"M_IP\"]}'
            ]
            
            with open('commands_fixed.txt', 'r') as stdin_file:
                subprocess.run(ssh_cmd, stdin=stdin_file)
                
            os.system('rm -f commands.txt commands_fixed.txt /tmp/id_rsa_fixed 2>/dev/null')
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
"
    sleep "$RUN_INTERVAL"
done