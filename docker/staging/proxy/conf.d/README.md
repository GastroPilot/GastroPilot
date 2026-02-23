# Proxy vhost-Configs (conf.d)

Nur **Dateien mit Endung `.conf`** in diesem Ordner werden vom Proxy geladen.

- **Aktive Configs:** z. B. `stage.gpilot.app.conf`, `stage-api.gpilot.app.conf` (werden von `install.sh` angelegt)
- **Vorlagen:** siehe Unterordner `examples/` (`.example`-Dateien werden **nicht** geladen)

Damit das Frontend erreichbar ist:

1. Staging-Stack muss laufen: `docker ps` → Container `gastropilot-staging-nginx` und `gastropilot-staging-backend` vorhanden
2. Beide müssen im gleichen Netz wie der Proxy:  
   `docker network inspect gastropilot-staging-proxy` → Liste enthält `gastropilot-staging-nginx` und `gastropilot-staging-proxy`
3. Aufruf mit der konfigurierten Domain (z. B. `https://stage.gpilot.app` oder `https://www.stage.gpilot.app`), nicht per IP

Bei Problemen: Proxy-Logs prüfen:  
`docker logs gastropilot-staging-proxy` und ggf. `docker exec gastropilot-staging-proxy cat /var/log/nginx/error.log`
