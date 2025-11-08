using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.Json;
using Dapr.Client;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Options;
using Planets.Api.Data;
using Planets.Api.Models;
using Planets.Api.Options;

namespace Planets.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Route("[controller]")]
[Route("planets")] // explicit for clarity
public class PlanetsController(
    IPlanetRepository repository,
    DaprClient daprClient,
    IOptions<NasaNeoFeedOptions> options,
    ILogger<PlanetsController> logger) : ControllerBase
{
    private readonly IPlanetRepository _repository = repository;
    private readonly DaprClient _daprClient = daprClient;
    private readonly ILogger<PlanetsController> _logger = logger;
    private readonly NasaNeoFeedOptions _options = options.Value;

    [HttpGet]
    public ActionResult<IEnumerable<Planet>> GetAll()
    {
        var planets = _repository.GetAll().ToList();
        _logger.LogInformation("Retrieved {Count} planets.", planets.Count);
        return Ok(planets);
    }

    [HttpGet("{id:int}")]
    public ActionResult<Planet> GetById(int id)
    {
        var planet = _repository.GetById(id);
        if (planet is null)
        {
            _logger.LogWarning("Planet with id {Id} not found.", id);
            return NotFound();
        }

        _logger.LogInformation("Retrieved planet {Name} (Id: {Id}).", planet.Name, planet.Id);
        return Ok(planet);
    }

    [HttpGet("asteroids")]
    public async Task<ActionResult<AsteroidFeedResult>> GetAsteroidsAsync([FromQuery] string? date, CancellationToken cancellationToken)
    {
        if (!TryResolveDate(date, out var fetchDate, out var errorMessage))
        {
            return BadRequest(new { message = errorMessage });
        }
        var dateString = fetchDate.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

        var componentName = string.IsNullOrWhiteSpace(_options.ComponentName)
            ? "nasa-neo-feed"
            : _options.ComponentName;
        var path = string.IsNullOrWhiteSpace(_options.Path)
            ? "/neo/rest/v1/feed"
            : _options.Path.Trim();
        path = path.StartsWith('/') ? path : "/" + path;
        var apiKey = string.IsNullOrWhiteSpace(_options.ApiKey)
            ? "DEMO_KEY"
            : _options.ApiKey!;
        if (string.Equals(apiKey, "DEMO_KEY", StringComparison.OrdinalIgnoreCase))
        {
            _logger.LogWarning("NASA API key is configured as DEMO_KEY; this key is heavily rate limited and may return 403 responses. Configure NASA__NeoFeed__ApiKey with your issued key.");
        }

        var query = $"start_date={dateString}&end_date={dateString}&detailed={_options.Detailed.ToString().ToLowerInvariant()}&api_key={Uri.EscapeDataString(apiKey)}";

        var fullPath = string.IsNullOrEmpty(query) ? path : $"{path}?{query}";
        var headersValue = string.Join('&', new[]
        {
            "User-Agent=planets-backend/1.0 (github.com/ivee-tech/aca-lz-cx)",
            "Accept=application/json"
        });
        var metadata = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["path"] = fullPath,
            ["method"] = "GET",
            ["headers"] = headersValue
        };

        var maskedQuery = MaskApiKeyInQuery(query);
        var requestUrl = string.IsNullOrEmpty(maskedQuery)
            ? $"https://api.nasa.gov{path}"
            : $"https://api.nasa.gov{path}?{maskedQuery}";
    var metadataSummary = string.Join(", ", metadata.Select(kv => $"{kv.Key}={kv.Value}"));
    _logger.LogInformation("Calling NASA NEO feed via component {Component} | Url: {Url} | Detailed: {Detailed} | Date: {Date}", componentName, requestUrl, _options.Detailed, fetchDate);
    _logger.LogDebug("Dapr metadata for NASA call: {Metadata}", metadataSummary);

        try
        {
            // Dapr binding keeps the HTTP call configuration declarative so the controller only supplies query details.
            var bindingRequest = new BindingRequest(componentName, "get")
            {
                Data = BinaryData.FromBytes(Array.Empty<byte>())
            };
            foreach (var kvp in metadata)
            {
                bindingRequest.Metadata.Add(kvp.Key, kvp.Value);
            }

            var bindingResponse = await _daprClient.InvokeBindingAsync(bindingRequest, cancellationToken);
            var dataMemory = bindingResponse.Data;
            var payload = dataMemory.IsEmpty ? null : Encoding.UTF8.GetString(dataMemory.ToArray());

            if (string.IsNullOrWhiteSpace(payload))
            {
                _logger.LogWarning("NASA NEO feed returned an empty payload for {Date} via component {Component}.", fetchDate, componentName);
                return StatusCode(StatusCodes.Status502BadGateway, "NASA feed returned an empty payload.");
            }

            var result = AsteroidFeedResult.FromJson(payload, fetchDate);
            _logger.LogInformation("NASA NEO feed returned {Total} objects for {Date} (component {Component}).", result.TotalCount, fetchDate, componentName);
            return Ok(result);
        }
        catch (JsonException ex)
        {
            _logger.LogError(ex, "Failed to parse NASA asteroid payload for {Date}.", fetchDate);
            return StatusCode(StatusCodes.Status502BadGateway, "NASA asteroid feed payload was invalid.");
        }
        catch (Exception ex)
        {
            var detail = ex.InnerException?.Message ?? ex.Message;
            _logger.LogError(ex, "Dapr binding {Component} failed while retrieving asteroid data for {Date}. Detail: {Detail}", componentName, fetchDate, detail);
            return StatusCode(StatusCodes.Status502BadGateway, "Failed to retrieve NASA asteroid feed.");
        }
    }

    private static string MaskApiKeyInQuery(string query)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            return query;
        }

        var parts = query.Split('&', StringSplitOptions.RemoveEmptyEntries);
        for (var i = 0; i < parts.Length; i++)
        {
            if (parts[i].StartsWith("api_key=", StringComparison.OrdinalIgnoreCase))
            {
                var value = parts[i].Substring("api_key=".Length);
                parts[i] = $"api_key={(string.IsNullOrEmpty(value) ? "<empty>" : MaskValue(value))}";
            }
        }

        return string.Join('&', parts);
    }

    private static string MaskValue(string value)
    {
        if (value.Length <= 4)
        {
            return new string('*', value.Length);
        }

        var visible = value[^4..];
        return new string('*', value.Length - 4) + visible;
    }

    private static bool TryResolveDate(string? date, out DateOnly resolved, out string? error)
    {
        if (string.IsNullOrWhiteSpace(date))
        {
            resolved = DateOnly.FromDateTime(DateTime.UtcNow.Date);
            error = null;
            return true;
        }

        if (DateOnly.TryParseExact(date, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsed))
        {
            resolved = parsed;
            error = null;
            return true;
        }

        resolved = default;
        error = "Date must be provided in yyyy-MM-dd format.";
        return false;
    }
}
