```
docker run --name oracle-db --restart always -p 1521:1521 -e ORACLE_PWD=oracle -e ORACLE_CHARACTERSET=AL32UTF8 -e ENABLE_ARCHIVELOG=true -e ENABLE_FORCE_LOGGING=true -v oracle-db:/opt/oracle/oradata container-registry.oracle.com/database/free:latest
```
