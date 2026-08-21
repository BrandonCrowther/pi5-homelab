# Docker daemon config

`daemon.json` sets the host-wide default logging policy: 3 rotated files of
10 MB per container, so ~30 MB worst case each. Without it, Docker's default is
an uncapped `json-file`, which is what let a few containers here grow without
limit.

Every stack in this repo also declares the same `logging:` block explicitly, so
it does not depend on this file. The daemon default exists to catch what the
repo does not: `docker run` one-offs, and any new stack whose compose file
forgets the block.

Note that `json-file` has no time-based retention — there is no "keep 7 days"
option, only size. 30 MB is roughly a week for the noisiest service here (Home
Assistant, ~6 MB/day) and far longer for everything else.

## Install

```sh
sudo install -m 0644 docker/daemon.json /etc/docker/daemon.json
sudo systemctl restart docker   # restarts all containers
```

The restart is only needed to pick up the default. Existing containers keep the
policy they were created with; changing a compose `logging:` block requires
`docker compose up -d --force-recreate` for that stack, since log options are
fixed when the container is created.
