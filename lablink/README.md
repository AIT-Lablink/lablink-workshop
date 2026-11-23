# SimpleDH Lablink: hub / station split

```
hub/                          station/
  docker-compose.yml            docker-compose.yml
  .env.example                  .env.example
  gen_config.py
  config/                       (needs ../display/substation)
    mosquitto.conf
    nginx.conf.template
    index.html, styles.css
    simpledh-config.db  <- generated
```

## Hub host

```sh
cd hub
cp .env.example .env                       # set HUB_IP, STATION_IP
python gen_config.py --hub-ip 192.168.10.10 --station-ip 192.168.10.20
docker compose up -d
docker compose --profile fmusim run --rm --no-deps fmusim
```

Open the firewall for 1883/tcp (MQTT) and 8080/tcp (reverse proxy) from the stations.
The stations fetch their configs through the proxy at `/config/get`; the config
server port 10101 is not published.
The web entry point is `http://HUB_IP:8080/`.

## Station host

```sh
cd station
cp .env.example .env                       # set HUB_IP
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
