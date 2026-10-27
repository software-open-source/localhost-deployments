```
docker run --restart always -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=07_n0TAPqwd\" -p 1433:1433 --name sql-server -d mcr.microsoft.com/mssql/server:2022-latest

docker cp AdventureWorks2022.bak sql-server:/var/opt/mssql/data/
```

docker run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=YourStrong(!)Password2026" -p 1433:1433 --name sql_server -d mcr.microsoft.com/mssql/server


docker run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=Password2026" -e "MSSQL_PID=Evaluation" -p 1433:1433  --name sql2025 --hostname sql2025 -d mcr.microsoft.com/mssql/server:2025-latest