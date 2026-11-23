FROM python:3.8-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY simpledh-opcua-server.py index.html app.js styles.css ./

# Address clients connect to. The process listens on 0.0.0.0; this host is not bound.
ENV OPCUA_ENDPOINT=opc.tcp://host.docker.internal:12345/simpledh

EXPOSE 12345 80
ENTRYPOINT ["python", "-u", "simpledh-opcua-server.py"]
