# PiHole + Unbound

<!--toc:start-->

- [PiHole + Unbound](#pihole-unbound)
  - [Setup](#setup)
  - [Troubleshooting](#troubleshooting)
  <!--toc:end-->

## Setup

1. Copy `env.template` to `.env`
2. Set password to preference. Can always change this later.
3. `docker compose up -d` to start PiHole and Unbound.
4. In PiHole admin <http://pi.hole>, set up DHCP if on Bell Router.
5. Still in PiHole admin, go to DNS and set your upstream DNS to `127.0.0.1#5335`.
6. Log into your router and point your router's DNS at your server's IP address. If needed, also adjust DHCP settings (Bell stuff)
7. On a test device, reconnect to your wifi and test. Devices will cache the old network, so devices will need to be restarted.

## Troubleshooting

- Check unbound is working `dig @127.0.0.1 -p 5335 google.com`.
- Fuck Bell routers and fuck you Bell
