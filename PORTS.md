# Port allocation — Collaboration keeps 3000. Housekeeper uses 3001. Metro keeps 8081.

Do not put two owners on the same port.

| Port | Owner | URL |
|------|--------|-----|
| **3000** | Collaboration frontend (local Next) | http://localhost:3000 |
| **3001** | Housekeeper web (Docker) | http://localhost:3001 |
| **4000** | Housekeeper API (Docker) | http://localhost:4000/api/v1 |
| **5000** | Collaboration backend (local Nest) | http://localhost:5000/api/v1 |
| **5433** | Housekeeper Postgres | |
| **5434** | Collaboration Postgres | |
| **6380** | Housekeeper Redis | |
| **6381** | Collaboration Redis | |
| **8080** | Jenkins | http://localhost:8080 |
| **8081** | Expo Metro (mobile) | http://localhost:8081 |
| **8082** | Housekeeper Adminer | http://localhost:8082 |
| **8083** | Collaboration Adminer | http://localhost:8083 |
| **9200** | Collaboration Elasticsearch | http://localhost:9200 |
| **9443** | Portainer | https://localhost:9443 |

Collaboration Adminer: System PostgreSQL, server `db`, user `postgres`, password `collab_secret`, database `selamnew-collab`.

Never run local Next **and** `collaboration-frontend-1` together (both want 3000).
Never run local Nest **and** `collaboration-backend-1` together (both want 5000).

Check live: `./ports.sh` from the Collaboration workspace.
