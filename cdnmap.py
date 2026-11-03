#!/usr/bin/env python3

import argparse
import sys
import re
import http.client
import ssl
from urllib.parse import urlparse
from collections import deque, defaultdict
import ipaddress
import threading
import time
import os
import socket


MAX_REDIRECT_DEPTH = 5
TIMEOUT_SECONDS = 10
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/91.0.4472.124"


class Spinner:
    def __init__(self):
        self._stop_event = threading.Event()
        self.message_prefix = ""
        self.waiting_seconds = 0

    def start(self):
        self._stop_event.clear()
        self.thread = threading.Thread(target=self._animate, daemon=True)
        self.thread.start()

    def stop(self):
        self._stop_event.set()
        if hasattr(self, 'thread') and self.thread.is_alive():
            self.thread.join()
        sys.stdout.write('\r' + ' ' * 70 + '\r')
        sys.stdout.flush()

    def _animate(self):
        chars = ['|', '/', '-', '\\']
        idx = 0
        last_sec_update = time.time()

        while not self._stop_event.is_set():
            char = chars[idx % len(chars)]

            if self.waiting_seconds > 0:
                msg = f"{self.message_prefix}Waiting {self.waiting_seconds}s... {char}"
                if time.time() - last_sec_update >= 1.0:
                    self.waiting_seconds -= 1
                    last_sec_update = time.time()
            else:
                msg = f"{self.message_prefix}Processing... {char}"

            sys.stdout.write(f'\r{msg.ljust(65)}')
            sys.stdout.flush()

            idx += 1
            time.sleep(0.1)


def aggregate_ips(ip_list):
    valid_ipv4 = []
    for ip_str in ip_list:
        try:
            addr = ipaddress.ip_address(ip_str)
            if isinstance(addr, ipaddress.IPv4Address) and not addr.is_loopback:
                valid_ipv4.append(addr)
        except ValueError:
            continue

    subnet_map = defaultdict(list)
    for ip in valid_ipv4:
        net = ipaddress.ip_network(f"{ip}/24", strict=False)
        subnet_map[net].append(ip)

    aggregated_cidrs = []
    remaining_ips = []

    for net, ips in subnet_map.items():
        if len(ips) >= 3:
            aggregated_cidrs.append(str(net))
        else:
            remaining_ips.extend(ips)

    networks_to_collapse = [ipaddress.ip_network(f"{ip}/24", strict=False) for ip in remaining_ips]

    if networks_to_collapse:
        collapsed_nets = list(ipaddress.collapse_addresses(networks_to_collapse))
        aggregated_cidrs.extend([str(n) for n in collapsed_nets])

    unique_sorted_cidrs = sorted(set(aggregated_cidrs), key=lambda x: ipaddress.ip_network(x))
    return unique_sorted_cidrs


class CDNCrawler:
    def __init__(self, target_domain=None, initial_domains=None):
        self.initial_domains = initial_domains
        self.dns_only_mode = bool(initial_domains)
        
        if initial_domains:
            self.target = initial_domains[0]
            self.found_domains = set(initial_domains)
        else:
            parsed = urlparse(f"http://{target_domain}")
            self.target = parsed.netloc or parsed.path
            self.found_domains = {self.target}

        self.found_ips = set()
        socket.setdefaulttimeout(TIMEOUT_SECONDS)

    def run(self, quiet=False, skip_crawl=False):
        if not quiet and not skip_crawl:
            print(f"[+] Crawling and analyzing content for: {self.target}", file=sys.stdout)

        if not skip_crawl:
            queue = deque([(self.target, 0)])
            visited_hosts = set()

            while queue:
                current_host, depth = queue.popleft()

                if current_host in visited_hosts or depth >= MAX_REDIRECT_DEPTH:
                    continue

                visited_hosts.add(current_host)
                self._fetch_and_follow(current_host, depth + 1, queue, sys.stdout, quiet=quiet)

        if not quiet:
            print(f"\n[*] Resolving IPs for {len(self.found_domains)} domains...", file=sys.stdout)

        resolved_count = 0

        domains_to_resolve = list(self.found_domains)

        for domain in domains_to_resolve:
            try:
                results = socket.getaddrinfo(domain, None, socket.AF_INET, socket.SOCK_STREAM)
                for item in results:
                    ip = item[4][0]
                    self.found_ips.add(ip)
                resolved_count += 1
            except Exception:
                pass

        if not quiet:
            print(f"[*] Successfully resolved IPs for {resolved_count} hosts. Found {len(self.found_ips)} unique IPs.", file=sys.stdout)

    def _fetch_and_follow(self, host, depth, queue, output_file, quiet=False):
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

        try:
            conn = http.client.HTTPSConnection(host, timeout=TIMEOUT_SECONDS, context=ctx)
            conn.request("GET", "/", headers={"User-Agent": USER_AGENT})
            response = conn.getresponse()

            if 300 <= response.status < 400:
                location = response.getheader("Location")
                if location:
                    parsed_loc = urlparse(location)
                    new_host = parsed_loc.netloc

                    if new_host and new_host not in self.found_domains:
                        if not quiet:
                            print(f"    -> Redirect to: {new_host}", file=output_file)
                        self.found_domains.add(new_host)
                        queue.append((new_host, depth))

            try:
                body = response.read().decode('utf-8', errors='ignore')

                patterns = [r'(?:src|href)=["\']((?:(?:https?):)?//[^\\\"\']+)', r'url\(["\']?(?:(?:https?):)?//([^\\\"\']*)["\']?\)']

                for pattern in patterns:
                    matches = re.finditer(pattern, body)
                    for match in matches:
                        url = match.group(1).rstrip('/')

                        if not url.startswith(('http:', 'https:')):
                            url = 'https:' + url

                        parsed_url = urlparse(url)
                        asset_host = parsed_url.netloc

                        if asset_host and asset_host != self.target and '.' in asset_host:
                            if asset_host not in self.found_domains:
                                if not quiet:
                                    print(f"    -> Found Asset Host: {asset_host}", file=output_file)
                                self.found_domains.add(asset_host)

            except Exception as e:
                pass

            conn.close()
        except Exception as e:
            pass

    def generate_results(self, mode='verbose', list_name=None):
        output_buffer = []

        if mode == 'mikrotik':
            optimized_rules = aggregate_ips(list(self.found_ips))

            output_buffer.append("/ip firewall address-list remove [find where list=\"{}\"]".format(list_name))
            for cidr in optimized_rules:
                output_buffer.append("/ip firewall address-list add list=\"{}\" address={}".format(list_name, cidr))
        else:
            output_buffer.append("\n" + "="*40)
            output_buffer.append("RESULTS")
            output_buffer.append("="*40)

            output_buffer.append(f"\nTotal Domains ({len(self.found_domains)}):")
            for d in sorted(self.found_domains):
                output_buffer.append(f"  - {d}")

            output_buffer.append(f"\nTotal IPs ({len(self.found_ips)}):")
            try:
                 ips_list = list(self.found_ips)
                 ips_list.sort(key=lambda x: (ipaddress.ip_address(x).version, ipaddress.ip_address(x)))

                 for ip in ips_list:
                    output_buffer.append(f"  - {ip}")

                 optimized_rules = aggregate_ips(ips_list)
                 if optimized_rules:
                     output_buffer.append(f"\nOptimized Firewall Rules ({len(optimized_rules)} CIDR blocks):")
                     for cidr in optimized_rules:
                         output_buffer.append(f"  - {cidr}")
            except ImportError:
                for ip in sorted(self.found_ips):
                    output_buffer.append(f"  - {ip}")

        return "\n".join(output_buffer)


def main():
    parser = argparse.ArgumentParser(description="CDN Crawler with Content Scanning")
    parser.add_argument("-v", "--version", action="version", version="%(prog)s 1.0.4")
    parser.add_argument("-o", "--output", type=str, help="Output results to a text file (e.g., output.txt)")
    parser.add_argument("-m", "--mikrotik", nargs='?', const='', default=None, help="Name of MikroTik address list")

    parser.add_argument("-i", "--iterations", type=int, default=1, help="Number of scanning iterations")
    parser.add_argument("-d", "--delay", type=int, default=0, help="Delay in seconds between iterations")

    parser.add_argument("domain", nargs='?', default=None, help="Target domain (e.g., instagram.com)")
    parser.add_argument("--list", type=str, default=None, help="Comma-separated list of domains/subdomains for DNS-only mode")
    
    args = parser.parse_args()

    if not args.domain and not args.list:
        parser.error("Must specify target domain or --list argument")
        
    if args.delay > 0 and args.iterations <= 1:
        parser.error("Flag -d/--delay can only be used together with flag -i/--iterations (where iteration count is greater than 1).")

    initial_domains = None
    skip_crawl = False
    
    if args.list:
        initial_domains = [d.strip() for d in args.list.split(',') if d.strip()]
        skip_crawl = True
        
    crawler = CDNCrawler(args.domain, initial_domains=initial_domains)

    use_spinner = bool(args.output or args.mikrotik is not None)
    spinner = Spinner()

    try:
        if use_spinner:
            spinner.start()

        for current_iter in range(1, args.iterations + 1):
            spinner.message_prefix = f"[{current_iter}/{args.iterations}] "
            spinner.waiting_seconds = 0

            crawler.run(quiet=use_spinner, skip_crawl=skip_crawl)

            if current_iter < args.iterations and args.delay > 0:
                if use_spinner:
                    spinner.waiting_seconds = args.delay
                    while spinner.waiting_seconds > 0:
                        time.sleep(0.1)
                else:
                    print(f"[*] Waiting {args.delay}s before next iteration...")
                    time.sleep(args.delay)

        if use_spinner:
            spinner.stop()

        result_mode = 'verbose'
        final_list_name = ''

        if args.mikrotik is not None and args.output:
            result_mode = 'mikrotik'

            if args.mikrotik == '':
                final_list_name = os.path.splitext(os.path.basename(args.output))[0]
            else:
                final_list_name = args.mikrotik

            with open(args.output, 'w', encoding='utf-8') as f:
                content = crawler.generate_results(mode=result_mode, list_name=final_list_name)
                f.write(content + "\n")

        elif args.mikrotik is not None:
            result_mode = 'mikrotik'

            if args.mikrotik == '':
                target_source = args.domain if args.domain else (initial_domains[0] if initial_domains else "unknown")
                final_list_name = target_source.replace(".", "_")
            else:
                final_list_name = args.mikrotik

            print("\n" + crawler.generate_results(mode=result_mode, list_name=final_list_name))

        elif args.output:
            with open(args.output, 'w', encoding='utf-8') as f:
                content = crawler.generate_results(mode='verbose')
                f.write(content + "\n")

        else:
            print(crawler.generate_results(mode='verbose'))

    finally:
        if use_spinner:
            if args.output and not args.mikrotik:
                print(f"[+] Output successfully saved to {args.output}")
            elif args.output and args.mikrotik is not None:
                print(f"[+] MikroTik script saved to {args.output}")


if __name__ == "__main__":
    main()