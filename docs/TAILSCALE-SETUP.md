# Tailscale Setup for UnifyOps Infrastructure

This guide helps you set up Tailscale for secure remote access to your UnifyOps server from anywhere.

## What is Tailscale?

Tailscale creates a secure, encrypted peer-to-peer VPN mesh network between your devices. It uses WireGuard under the hood and handles all the complex networking automatically.

## Installation

### Step 1: Install Tailscale on Server

SSH into your server and run the installation script:

```bash
# Copy and run the installation script
scp scripts/install-tailscale.sh unifyops:~/
ssh unifyops
chmod +x install-tailscale.sh
./install-tailscale.sh
```

### Step 2: Connect to Tailscale Network

Choose one of the following configuration options:

#### Option A: Basic Access (Recommended for getting started)
```bash
# Simple connection - access server directly
sudo tailscale up
```

#### Option B: SSH-Only Access
```bash
# Enable Tailscale SSH (no need for SSH keys)
sudo tailscale up --ssh
```

#### Option C: Subnet Router (Access Kubernetes cluster and local network)
```bash
# Run the configuration script with subnet routing
./tailscale-config.sh --subnet-router
```

#### Option D: Exit Node (Use server as VPN)
```bash
# Configure server as an exit node
./tailscale-config.sh --exit-node
```

#### Option E: Full Setup (All features)
```bash
# Enable SSH, subnet routing, and exit node
./tailscale-config.sh --ssh --subnet-router --exit-node
```

### Step 3: Authenticate

1. When you run `tailscale up`, you'll get an authentication URL
2. Open the URL in your browser
3. Log in with your preferred identity provider (Google, Microsoft, GitHub, etc.)
4. Authorize the device

### Step 4: Install Tailscale on Your Client Devices

Download and install Tailscale on your devices:
- **macOS/Windows/Linux**: https://tailscale.com/download
- **iOS/Android**: Install from App Store or Google Play

## Accessing Your Server

Once connected, you can access your server using its Tailscale IP or hostname:

```bash
# Get your server's Tailscale IP
tailscale ip -4

# View all devices in your network
tailscale status

# SSH using Tailscale hostname (if SSH is enabled)
ssh user@um790  # or use the Tailscale IP

# If using Tailscale SSH
ssh root@um790  # No SSH keys needed!
```

## Accessing Kubernetes Services

If you enabled subnet routing, you can access your Kubernetes services directly:

```bash
# Access ArgoCD UI
http://argocd.local  # Will work from any Tailscale-connected device

# Access Longhorn UI  
http://longhorn.local

# Access Docker Registry
https://registry.local
```

## Advanced Features

### ACLs (Access Control Lists)

Tailscale supports fine-grained access control. Edit your ACL policy in the Tailscale admin console:
- https://login.tailscale.com/admin/acls

Example ACL for UnifyOps:
```json
{
  "acls": [
    // Allow all users to access the server
    {"action": "accept", "src": ["*"], "dst": ["um790:*"]},
    
    // Allow server to access the internet (if exit node)
    {"action": "accept", "src": ["um790"], "dst": ["*:*"]}
  ],
  
  "ssh": [
    // Allow SSH access to server
    {
      "action": "accept",
      "src": ["autogroup:members"],
      "dst": ["um790"],
      "users": ["root", "ubuntu", "unifyops"]
    }
  ]
}
```

### MagicDNS

Enable MagicDNS in the Tailscale admin console to use hostnames instead of IPs:
1. Go to https://login.tailscale.com/admin/dns
2. Enable MagicDNS
3. Now you can use `um790` instead of the IP address

### Exit Node Usage

If you configured your server as an exit node:

1. On your client device, go to Tailscale settings
2. Select "Exit Node" → Choose your server
3. All your internet traffic will now route through your server

This is useful for:
- Accessing geo-restricted content
- Securing your connection on public WiFi
- Accessing services that are IP-restricted to your server

## Security Benefits

1. **End-to-End Encryption**: All traffic is encrypted using WireGuard
2. **No Open Ports**: Tailscale doesn't require opening firewall ports
3. **Identity-Based Access**: Uses your existing identity provider (Google, Microsoft, GitHub)
4. **Zero Trust Network**: Each connection is authenticated and encrypted
5. **Automatic Key Rotation**: Keys are automatically rotated for security

## Troubleshooting

### Check Tailscale Status
```bash
# View connection status
tailscale status

# View network interfaces
tailscale netcheck

# View Tailscale IP
tailscale ip -4
```

### Restart Tailscale
```bash
sudo systemctl restart tailscaled
```

### View Logs
```bash
sudo journalctl -u tailscaled -f
```

### Common Issues

1. **Cannot connect after installation**
   - Ensure you've authenticated via the URL provided
   - Check firewall rules: `sudo ufw status`
   - Verify service is running: `sudo systemctl status tailscaled`

2. **Subnet routes not working**
   - Enable IP forwarding: `sudo sysctl -w net.ipv4.ip_forward=1`
   - Approve subnet routes in Tailscale admin console
   - Check ACLs allow the traffic

3. **Exit node not working**
   - Ensure IP forwarding is enabled
   - Check that exit node is enabled in admin console
   - Verify client has selected the exit node

## Maintenance

### Updating Tailscale
```bash
# Ubuntu/Debian
sudo apt-get update && sudo apt-get upgrade tailscale

# RHEL/CentOS
sudo yum update tailscale
```

### Removing Tailscale
```bash
# Disconnect from network
sudo tailscale down

# Logout
sudo tailscale logout

# Uninstall (Ubuntu/Debian)
sudo apt-get remove tailscale

# Uninstall (RHEL/CentOS)  
sudo yum remove tailscale
```

## Cost

Tailscale offers a generous free tier:
- Free for personal use (up to 20 devices)
- Free for open source projects
- Paid plans for teams and enterprises

See pricing: https://tailscale.com/pricing

## Next Steps

1. Install Tailscale on all devices you want to connect
2. Configure ACLs for fine-grained access control
3. Enable MagicDNS for easier hostname access
4. Consider setting up Tailscale on your Kubernetes pods for secure pod-to-pod communication
5. Explore Tailscale Funnel for exposing services to the internet securely

## Resources

- Official Docs: https://tailscale.com/kb
- Admin Console: https://login.tailscale.com
- Community Forum: https://forum.tailscale.com
- GitHub: https://github.com/tailscale/tailscale