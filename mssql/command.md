```
docker run --restart always -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=07_n0TAPqwd\" -p 1433:1433 --name sql-server -d mcr.microsoft.com/mssql/server:2022-latest

docker cp AdventureWorks2022.bak sql-server:/var/opt/mssql/data/
```
