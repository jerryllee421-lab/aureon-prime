FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY src/Aureon.Core/Aureon.Core.csproj src/Aureon.Core/
COPY src/Aureon.Prime/Aureon.Prime.csproj src/Aureon.Prime/
COPY tests/Aureon.Core.SmokeTests/Aureon.Core.SmokeTests.csproj tests/Aureon.Core.SmokeTests/

RUN dotnet restore src/Aureon.Prime/Aureon.Prime.csproj
RUN dotnet restore tests/Aureon.Core.SmokeTests/Aureon.Core.SmokeTests.csproj

COPY . .

RUN dotnet run --project tests/Aureon.Core.SmokeTests/Aureon.Core.SmokeTests.csproj -c Release --no-restore
RUN dotnet build src/Aureon.Prime/Aureon.Prime.csproj -c Release --no-restore -p:AlgoPublish=false

CMD ["bash", "-lc", "find src/Aureon.Prime/bin/Release -type f -name '*.algo' -print"]
