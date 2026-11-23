# SimpleDH Lablink: hub / station split

## Hub host

The number of substations is configured via `SUBSTATIONS` in `gen_config.py` and `network-display/app.js` (needs rebuild).

In directoy `lablink/hub` edit `network.yaml`, which lists the hub address and one IP per substation.
Station number k is FMU substation k.
On that station host, set `OPCUA_CONFIG=stationk` so the client loads its own endpoint and client name.
The committed station compose uses `station1`.

Then, in directoy `lablink/hub`:
```sh
python gen_config.py
docker compose build
docker compose up -d
docker compose --profile fmusim run --rm --no-deps fmusim
```

The last command opens a Lablink terminal to the FMU simulator.
Change the DH network supply temperature with the following command:
```sh
svd TSupSet 358
```

Open the firewall for 1883/tcp (MQTT) and 8080/tcp (reverse proxy) from the stations.
The stations fetch their configs through the proxy at `/config/get`; the config
server port 10101 is not published.
The web entry point is `http://HUB_IP:8080/`.

## Station host

In directory `lablink/station`:
```sh
cp .env.example .env # set HUB_IP
docker compose build
docker compose up -d
```

Substation display availalbe at: http://localhost:8091

## Note for Linux users

Docker Desktop defines `host.docker.internal` inside containers.
Docker Engine on Linux leaves that name unset, so each container needs an explicit hosts entry:

```sh
docker run --add-host=host.docker.internal:host-gateway ...
```sh

In Compose:

```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

That name reaches a service on the host when the service listens on the bridge address (`0.0.0.0`) and the host firewall allows the container subnet through to that address.
