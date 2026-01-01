# Pi-hole Docker Architecture

## Service Overview

### Pi-hole (pihole)

**Purpose**: DNS server with ad-blocking capabilities and DHCP server for the local network.

**What it does**:

- Receives DNS queries from devices on your LAN (192.168.2.0/24)
- Blocks ads and trackers by returning null responses for blacklisted domains
- Forwards legitimate DNS queries to Unbound for resolution
- Acts as DHCP server, assigning IP addresses to devices on your network (replacing Bell router's DHCP)
- Provides web interface for management and statistics

**Network**: Bridge network (dns_network) with port mappings to host

### Unbound (unbound)

**Purpose**: Recursive DNS resolver that queries upstream DNS servers.

**What it does**:

- Receives DNS queries from Pi-hole
- Forwards queries to Cloudflare DNS (1.1.1.1 and 1.0.0.1)
- Caches responses for performance
- Provides privacy features (query minimization, etc.)

**Network**: Bridge network (dns_network) only

### DHCP Helper (dhcphelper)

**Purpose**: Bridges DHCP broadcast traffic between the host network and Pi-hole container.

**What it does**:

- Runs on host network to receive DHCP broadcast packets from LAN devices
- Forwards DHCP requests to Pi-hole container at 172.31.0.100
- Necessary because DHCP uses broadcast packets that don't cross Docker bridge networks naturally

**Network**: Host network (direct access to physical network)

## Network Flow

### DNS Query Flow

1. Device on LAN (e.g., 192.168.2.151) → Pi-hole at 192.168.2.207:53
2. Pi-hole checks blocklist:
   - If blocked: Returns null response
   - If allowed: Forwards to Unbound at 172.31.0.53:53
3. Unbound → Cloudflare DNS (1.1.1.1) for resolution
4. Response flows back: Cloudflare → Unbound → Pi-hole → Device

### DHCP Request Flow

1. Device broadcasts DHCP discover on LAN (192.168.2.0/24)
2. DHCP Helper (on host network) receives broadcast
3. DHCP Helper forwards to Pi-hole at 172.31.0.100
4. Pi-hole responds with IP lease, DNS server (itself), and gateway (Bell router)
5. Response flows back through DHCP Helper to device

### Web UI Access

1. Browser → <http://192.168.2.207:8080>
2. Host port 8080 → Pi-hole container port 80
3. Pi-hole web interface responds

## IP Address Map

### Physical Network (192.168.2.0/24)

- **192.168.2.1**: Bell router (gateway to internet)
- **192.168.2.207**: Pi5 host machine (where Docker runs)
- **192.168.2.x**: DHCP-assigned IPs for devices on LAN (managed by Pi-hole)

### Docker Bridge Network (172.31.0.0/16) - dns_network

- **172.31.0.53**: Unbound container
- **172.31.0.100**: Pi-hole container

## Port Mappings

### Pi-hole Container

- Host `53:53/tcp` → Container `53` (DNS over TCP)
- Host `53:53/udp` → Container `53` (DNS over UDP)
- Host `8080:80/tcp` → Container `80` (Web interface)

### Unbound Container

- No host ports exposed (only accessible from dns_network)
- Listens on `0.0.0.0:53` within container

## Why This Architecture?

### Bridge Networking

- Provides isolation between services and host
- Required for future orchestration and scaling
- Allows multiple services without port conflicts

### DHCP Helper

- Solves the broadcast packet problem with bridge networking
- Pi-hole can run DHCP without requiring host networking
- Necessary because Bell router doesn't allow disabling DHCP or changing DNS settings

### Separate DNS Network

- Isolates DNS infrastructure from other services
- Unbound only accessible to Pi-hole, not exposed to host or other containers
- Clean separation of concerns for future expansion
