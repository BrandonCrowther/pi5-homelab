# glances

[Glances](https://nicolargo.github.io/glances/) in web-server mode, reporting
this Pi's utilization. Runs on its own so anything that wants host metrics can
consume it without depending on a particular dashboard.

```sh
docker compose up -d
```

- Web UI: <http://192.168.2.2:61208>
- REST API: <http://192.168.2.2:61208/api/4/>

On the `traefik_backend` network other stacks reach it as `http://glances:61208`.
Home Assistant cannot: it runs `network_mode: host`, so it has no address on
that bridge and resolves no container names. Its Glances integration and the
`binary_sensor.status_glances_pi5` probe both use the published port below,
which is also what the browser and hand-run API calls use:

```sh
curl -s http://192.168.2.2:61208/api/4/sensors | jq '.[].label'
curl -s http://192.168.2.2:61208/api/4/fs | jq '.[].mnt_point'
```

## Two container details that matter

- **`pid: host`** — without it Glances only sees its own process namespace, so
  load and process counts describe the container, not the Pi.
- **`/:/rootfs:ro`** — filesystem stats come from the container's own mount
  namespace, which otherwise contains nothing but the bind mounts. Mounting
  the host root makes the real disk visible, but it appears under the path it
  was mounted at. **Consumers must ask for `/rootfs`, not `/`.** Change the
  mount here and every consumer has to change with it.

## Sensor labels

Hardware-specific, and consumers match on them by string. What this Pi reports:

| Label | Reads |
| --- | --- |
| `cpu_thermal 0` | CPU temperature, °C |
| `rp1_adc 0` | RP1 southbridge temperature, °C |
| `pwmfan 0` | Fan speed, RPM |

Re-check with the `sensors` call above after a kernel bump if a consumer's
temperature reading goes blank.

## Exposure

LAN only. The API is unauthenticated and read-only; it exposes process names,
mounted filesystems, and container names. No Traefik labels on purpose — put
auth in front of it before routing it off the LAN. Glances supports
`--password` if you'd rather lock it down in place, in which case consumers
need matching `username`/`password` in their widget config.
