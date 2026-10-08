# Moodle Setup

```bash
docker compose up -d
```

```bash
docker exec -it moodle sed -i 's/$CFG->sslproxy = true;/$CFG->sslproxy = false;/g' /var/www/html/config.php;
docker exec -it moodle sed -i 's/$CFG->reverseproxy = true;/$CFG->reverseproxy = false;/g' /var/www/html/config.php;
docker exec -it moodle sed -i 's|$CFG->wwwroot = .*$|$CFG->wwwroot = '\''http://localhost'\'';|g' /var/www/html/config.php;
```

```bash
docker compose restart
```