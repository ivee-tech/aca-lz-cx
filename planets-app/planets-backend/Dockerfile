# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ../Directory.Build.props ./
COPY planets-backend/*.csproj ./planets-backend/
RUN dotnet restore planets-backend/Planets.Api.csproj
COPY planets-backend/. ./planets-backend/
WORKDIR /src/planets-backend
RUN dotnet publish -c Release -o /app/publish /p:UseAppHost=false

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080
ENTRYPOINT ["dotnet", "Planets.Api.dll"]
