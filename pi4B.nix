{ pkgs, ... }: 

let
  customPython = pkgs.python3.withPackages (ps: with ps; [ flask ]);

  wifiDashboardScript = pkgs.writeText "wifi-dashboard.py" ''
    from flask import Flask, render_template_string
    import subprocess
    import re

    app = Flask(__name__)

    # Increased refresh to 30 seconds since an active Nmap sweep takes a few seconds to complete
    DASHBOARD_HTML = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <title>Network Telemetry</title>
        <meta http-equiv="refresh" content="30">
        <style>
            :root {
                --phosphor: #8fa876;
                --phosphor-dim: #4a5c3f;
                --bg: #121412;
                --alert: #a87676;
            }
            body { 
                font-family: "Courier New", Courier, monospace; 
                background: var(--bg); 
                color: var(--phosphor); 
                padding: 2rem; 
                margin: 0;
                text-shadow: 0 0 4px rgba(143, 168, 118, 0.4);
            }
            h1, h2 { text-transform: uppercase; border-bottom: 2px solid var(--phosphor-dim); padding-bottom: 0.5rem; }
            .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 1.5rem; margin-bottom: 2rem; }
            .card { background: transparent; padding: 1rem; border: 1px solid var(--phosphor-dim); }
            .val { font-size: 1.5rem; font-weight: bold; margin-bottom: 0.5rem; }
            .label { font-size: 0.85rem; text-transform: uppercase; color: var(--phosphor-dim); letter-spacing: 0.05em; }
            table { width: 100%; border-collapse: collapse; margin-top: 1rem; }
            th, td { text-align: left; padding: 0.5rem; border-bottom: 1px solid var(--phosphor-dim); }
            th { text-transform: uppercase; font-size: 0.85rem; }
            .vendor { color: var(--phosphor-dim); font-size: 0.85rem; }
        </style>
    </head>
    <body>
        <h1>[ SYSTEM_TELEMETRY_ON_WLAN0 ]</h1>
        
        <h2>Default Gateway (Router)</h2>
        <div class="grid">
            <div class="card">
                <div class="label">Gateway IP</div>
                <div class="val">{{ router.ip }}</div>
            </div>
            <div class="card">
                <div class="label">Ping Latency</div>
                <div class="val">{{ router.ping }}</div>
            </div>
        </div>

        <h2>Active Network Discovery (Nmap Sweep)</h2>
        <div class="card">
            <table>
                <tr><th>Hostname</th><th>IP Address</th><th>MAC Address</th><th>Hardware Vendor</th></tr>
                {% for device in network_devices %}
                <tr>
                    <td><strong>{{ device.name }}</strong></td>
                    <td>{{ device.ip }}</td>
                    <td>{{ device.mac }}</td>
                    <td class="vendor">{{ device.vendor }}</td>
                </tr>
                {% endfor %}
            </table>
        </div>

        <h2>RF Neighborhood (Visible APs)</h2>
        <div class="card">
            <table>
                <tr><th>BSSID</th><th>SSID</th><th>Signal</th><th>Channel</th></tr>
                {% for ap in access_points %}
                <tr>
                    <td>{{ ap.bssid }}</td>
                    <td>{{ ap.ssid }}</td>
                    <td>{{ ap.signal }}</td>
                    <td>{{ ap.channel }}</td>
                </tr>
                {% endfor %}
            </table>
        </div>
    </body>
    </html>
    """

    def run_cmd(cmd):
        try:
            return subprocess.check_output(cmd, text=True, stderr=subprocess.STDOUT)
        except Exception:
            return ""

    def get_router_info():
        router = {"ip": "Unknown", "ping": "Timeout"}
        ip_route = run_cmd(["ip", "route"])
        match = re.search(r'default via ([0-9.]+)', ip_route)
        if match:
            router["ip"] = match.group(1)
            ping_out = run_cmd(["ping", "-c", "1", "-W", "1", router["ip"]])
            time_match = re.search(r'time=([\d.]+ ms)', ping_out)
            if time_match:
                router["ping"] = time_match.group(1)
        return router

    def get_network_devices():
        devices = []
        try:
            # 1. Dynamically figure out the Pi's current subnet (e.g., 192.168.12.0/24)
            ip_out = run_cmd(["ip", "-o", "-f", "inet", "addr", "show", "wlan0"])
            match = re.search(r'inet ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+)', ip_out)
            if not match:
                return []
            
            # Format the IP/CIDR into a proper subnet for nmap
            ip_cidr = match.group(1)
            ip_parts = ip_cidr.split('/')[0].split('.')
            subnet = f"{ip_parts[0]}.{ip_parts[1]}.{ip_parts[2]}.0/{ip_cidr.split('/')[1]}"

            # 2. Run an active Nmap ping scan with DNS resolution
            nmap_out = run_cmd(["nmap", "-sn", subnet])
            
            current_device = {}
            for line in nmap_out.splitlines():
                if line.startswith("Nmap scan report for"):
                    if current_device.get("ip"):
                        devices.append(current_device)
                    current_device = {"ip": "", "mac": "Unknown", "name": "Unknown", "vendor": "Unknown"}
                    
                    # Nmap outputs either:
                    # "Nmap scan report for hostname.lan (192.168.x.x)" OR
                    # "Nmap scan report for 192.168.x.x"
                    parts = line.replace("Nmap scan report for ", "").strip().split(" ")
                    if len(parts) == 2:
                        current_device["name"] = parts[0]
                        current_device["ip"] = parts[1].strip("()")
                    else:
                        current_device["ip"] = parts[0]
                        current_device["name"] = "<No Hostname>"
                        
                elif line.startswith("MAC Address:"):
                    # Format: "MAC Address: AA:BB:CC:DD:EE:FF (Vendor Name)"
                    mac_parts = line.replace("MAC Address: ", "").split(" ", 1)
                    current_device["mac"] = mac_parts[0]
                    if len(mac_parts) > 1:
                        current_device["vendor"] = mac_parts[1].strip("()")
                        
            if current_device.get("ip"):
                devices.append(current_device)
                
        except Exception:
            pass
        return devices

    def get_wifi_scan(interface="wlan0"):
        networks = []
        scan_out = run_cmd(["iw", "dev", interface, "scan"])
        current_net = {}
        
        for line in scan_out.splitlines():
            line = line.strip()
            if line.startswith('BSS '):
                if current_net:
                    networks.append(current_net)
                bssid = line.split(' ')[1].split('(')[0]
                current_net = {'bssid': bssid, 'ssid': '<Hidden>', 'signal': 'N/A', 'channel': 'N/A'}
            elif line.startswith('SSID:'):
                current_net['ssid'] = line.split('SSID: ')[-1].strip() or '<Hidden>'
            elif line.startswith('signal:'):
                current_net['signal'] = line.split('signal: ')[-1].strip()
            elif '* primary channel:' in line or 'primary channel:' in line:
                current_net['channel'] = line.split('channel: ')[-1].strip()
            elif 'DS Parameter set: channel' in line:
                current_net['channel'] = line.split('channel ')[-1].strip()
                
        if current_net:
            networks.append(current_net)
            
        networks.sort(key=lambda x: float(re.search(r'-?\d+\.?\d*', x.get('signal', '-100')).group()) if x.get('signal') != 'N/A' else -100, reverse=True)
        return networks

    @app.route('/')
    def dashboard():
        return render_template_string(
            DASHBOARD_HTML, 
            router=get_router_info(),
            network_devices=get_network_devices(),
            access_points=get_wifi_scan()
        )

    if __name__ == '__main__':
        app.run(host='127.0.0.1', port=8080)
  '';

in
{
  environment.systemPackages = with pkgs; [
    bc
    curl
    fd
    unzip
    wget
    vim
    fastfetch
    iw
    wirelesstools
    vnstat
    iperf3
    nmap
    iproute2
    nettools
    iputils
  ];

  environment.sessionVariables = {
    EDITOR = "vim";
  };

  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
  };

  programs.git = {
    enable = true;
    package = pkgs.git;
    prompt.enable = true;
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ]; 

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    virtualHosts."_" = {
      default = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8080";
      };
    };
  };

  systemd.services.wifi-health-app = {
    description = "Wireless Network Health Dashboard";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    
    # Crucial: Nmap must be in the service execution path alongside the others
    path = with pkgs; [ iw iproute2 nettools iputils nmap ]; 
    
    serviceConfig = {
      ExecStart = "${customPython}/bin/python ${wifiDashboardScript}"; 
      Restart = "on-failure";
      RestartSec = "5s";
      User = "root"; 
    };
  };
}
