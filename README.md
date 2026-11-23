# Lablink Hands-on Workshop

Materials for a supervised hands-on session with [AIT Lablink](https://ait-lablink.readthedocs.io/en/latest/). Participants connect a station to a shared hub and change a district-heating substation load. The hub's simulator, plotters, and network display show the effect.

`lablink/` is the runnable example. The hub runs the MQTT broker, config server, SimpleDH network FMU, plotters, and network display. Each station runs an OPC UA substation and the Lablink OPC UA client, either from source or from a zip of container images. `docs/` holds the introductory slides and the Windows 11 tutorial guide.

Lablink's license is the [3-clause BSD license](https://ait-lablink.readthedocs.io/en/latest/availability.html#lablink-license).
