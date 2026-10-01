# Docker host config

Two things here are shared across stacks: the daemon's logging default, which
applies to every container on the host, and the definition of the
`traefik_backend` network, which every stack routed through traefik joins.
`include:` needs Docker Compose v2.20 or later.

## Logging: `daemon.json`

`daemon.json` is the only place log rotation is declared: 3 rotated files of
10 MB per container, so ~30 MB worst case each. No compose file in this repo
has a `logging:` block. Docker copies the daemon default into each container
when it is created, so `docker inspect` shows the same options either way:

```sh
docker inspect -f '{{json .HostConfig.LogConfig}}' <container>
# {"Type":"json-file","Config":{"max-file":"3","max-size":"10m"}}
```

This makes `daemon.json` a requirement, not a fallback. On a host without it,
Docker's default is an uncapped `json-file` and every container here grows its
log without limit, with no warning. Install it before bringing up any stack.

`json-file` has no time-based retention — there is no "keep 7 days" option,
only size. Home Assistant is by far the noisiest container (~6 MB/day), which
puts 30 MB at four or five days; everything else lasts far longer. If one
service ever needs more, give that service its own `logging:` block rather than
raising the default for all of them.

### Install

```sh
sudo install -m 0644 docker/daemon.json /etc/docker/daemon.json
sudo systemctl restart docker   # restarts all containers
```

Log options are fixed when a container is created. After changing
`daemon.json`, restart the daemon and then run
`docker compose up -d --force-recreate` in each stack to apply the new policy.

## Network: `compose.network.yaml`

`compose.network.yaml` declares `traefik_backend` as an external network under
the name `backend`. The traefik stack creates the network and keeps its own
definition, so bring traefik up first on a fresh host. That makes the name
`traefik_backend` appear twice on purpose: here and in
`../traefik/docker-compose.yaml`. Renaming the network means editing both.

## Adding a new stack

Logging needs nothing; the daemon default applies. To route the stack through
traefik, include the network file at the top of its compose file and attach
the service to `backend`:

```yaml
include:
  - ../docker/compose.network.yaml

services:
  myapp:
    image: example/myapp
    restart: unless-stopped
    networks:
      - backend
    labels:
      - "traefik.enable=true"
      # ...router labels...
```

Do not redeclare the network in the stack's own top-level `networks:`. Compose
accepts the duplicate without complaint, which is how the copies this file
replaced crept in.
