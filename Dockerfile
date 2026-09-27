# ASTRA LAB: deterministic research/safety image.
# cTrader .algo packaging is performed by scripts/build-cbot.sh using the
# official Spotware cTrader CLI container.

FROM mcr.microsoft.com/dotnet/sdk:8.0

WORKDIR /workspace

COPY src/Aureon.Core/Aureon.Core.csproj src/Aureon.Core/
COPY tests/Aureon.Core.SmokeTests/Aureon.Core.SmokeTests.csproj tests/Aureon.Core.SmokeTests/

RUN dotnet restore tests/Aureon.Core.SmokeTests/Aureon.Core.SmokeTests.csproj

COPY src/Aureon.Core src/Aureon.Core
COPY tests/Aureon.Core.SmokeTests tests/Aureon.Core.SmokeTests

RUN dotnet run --project tests/Aureon.Core.SmokeTests/Aureon.Core.SmokeTests.csproj -c Release --no-restore

CMD ["dotnet", "run", "--project", "tests/Aureon.Core.SmokeTests/Aureon.Core.SmokeTests.csproj", "-c", "Release", "--no-restore"]
