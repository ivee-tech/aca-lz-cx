# Simple multi-stage build for the sample API
# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# copy csproj & restore as distinct layer
COPY SimpleApi.csproj ./
RUN dotnet restore "SimpleApi.csproj"

# copy everything & publish
COPY . .
RUN dotnet publish "SimpleApi.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "SimpleApi.dll"]
