# SimpleApi (.NET 8 Minimal API)

A small sample API with a few demonstration endpoints, container-ready.

## Project Layout
```
api/
  SimpleApi/
    SimpleApi.csproj
    Program.cs
    Dockerfile
    .dockerignore
```

## Endpoints
| Method | Route        | Description                       |
|--------|-------------|-----------------------------------|
| GET    | /healthz     | Liveness/health check             |
| GET    | /api/hello   | Returns a greeting message        |
| GET    | /api/time    | Returns current UTC & machine     |
| POST   | /api/echo    | Echoes posted JSON payload        |

### Echo Request Body
```json
{
  "text": "sample",
  "number": 42
}
```

### Echo Response Body
```json
{
  "text": "sample",
  "number": 42,
  "receivedUtc": "2025-10-01T12:34:56.789Z"
}
```

## Prerequisites
- .NET 8 SDK (for local build / run)
- Docker (for container build)

## Run Locally (no Docker)
```pwsh
cd api/SimpleApi
# Restore & run
dotnet run
# Visit: http://localhost:5000/swagger (dev profile picks dynamic port; console will show actual URLs)
```

## Build & Run Container
```pwsh
cd api/SimpleApi
# Build image
docker build -t simpleapi:dev .
# Run container (maps 8080 in container to local 8080)
docker run -it --rm -p 8080:8080 simpleapi:dev
# Test
curl http://localhost:8080/api/hello
```

## Publish Image (example)
```pwsh
# Tag & push to ACR (replace <acrName>)
docker tag simpleapi:dev <acrName>.azurecr.io/simpleapi:latest
docker push <acrName>.azurecr.io/simpleapi:latest
```

## Notes
- Swagger UI enabled automatically in Development environment.
- Health endpoint kept short (`/healthz`) for typical probes.
- XML docs are generated; you can enrich records with summaries for richer OpenAPI metadata.

## Next Ideas
- Add authentication (e.g., Entra ID / OAuth 2.0).
- Add structured logging & OpenTelemetry exporter.
- Wire up GitHub Actions workflow for CI/CD and image push.
