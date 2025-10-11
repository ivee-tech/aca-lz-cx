using System.Text.Json;
using System.Text.Json.Serialization;
using System.Net.Http.Headers;
using System.Net.Http.Json; // For PostAsJsonAsync & ReadFromJsonAsync extensions
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace Planets.Api.Tests;

public class RocketStreamTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> _factory;
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter() }
    };

    public RocketStreamTests(WebApplicationFactory<Program> factory)
    {
        _factory = factory.WithWebHostBuilder(builder => { /* placeholder for future overrides */ });
    }

    [Fact(Timeout = 20000)]
    public async Task StreamReceivesPublishedMessage()
    {
        var client = _factory.CreateClient();
        var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10));

        // Start reading SSE stream
    var request = new HttpRequestMessage(HttpMethod.Get, "/api/rockets/stream");
    request.Headers.Accept.ParseAdd("text/event-stream");
    var streamResponse = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cts.Token);
    // Don't enforce success immediately; some servers mark aborted SSE as 499 after disposal. Just ensure initial code was 200 range.
    Assert.InRange((int)streamResponse.StatusCode, 200, 299);
        await using var bodyStream = await streamResponse.Content.ReadAsStreamAsync(cts.Token);
        using var reader = new StreamReader(bodyStream);

    // Allow a brief moment to ensure server loop subscribed before publishing
    await Task.Delay(150, cts.Token);
    // Publish a message after stream established
        var rocketId = Guid.NewGuid().ToString("N");
        var payload = new {
            source = "Earth",
            destination = "Mars",
            rocketId,
            launchTime = DateTimeOffset.UtcNow
        };
        var publishResponse = await client.PostAsJsonAsync("/api/rockets/publish", payload, JsonOpts, cts.Token);
        publishResponse.EnsureSuccessStatusCode();

        string? line;
        string? jsonLine = null;
        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (!cts.IsCancellationRequested && sw.Elapsed < TimeSpan.FromSeconds(10))
        {
            line = await reader.ReadLineAsync();
            if (line is null) continue; // keep waiting
            if (line.StartsWith("data: "))
            {
                jsonLine = line.Substring("data: ".Length);
                break;
            }
        }

        Assert.False(string.IsNullOrWhiteSpace(jsonLine), "Did not receive SSE data line in allotted time.");
        var msg = JsonSerializer.Deserialize<RocketMessageDto>(jsonLine!, JsonOpts);
        Assert.NotNull(msg);
        Assert.Equal(rocketId, msg!.RocketId);
        Assert.Equal("Earth", msg.Source);
        Assert.Equal("Mars", msg.Destination);
    }

    [Fact]
    public async Task LatestEndpointReturnsMostRecentMessage()
    {
        var client = _factory.CreateClient();
        var rocketId = Guid.NewGuid().ToString("N");
        var payload = new {
            source = "Venus",
            destination = "Jupiter",
            rocketId,
            launchTime = DateTimeOffset.UtcNow
        };
        var publishResponse = await client.PostAsJsonAsync("/api/rockets/publish", payload, JsonOpts);
        publishResponse.EnsureSuccessStatusCode();

        var latest = await client.GetAsync("/api/rockets/latest");
        latest.EnsureSuccessStatusCode();
        var dto = await latest.Content.ReadFromJsonAsync<RocketMessageDto>(JsonOpts);
        Assert.NotNull(dto);
        Assert.Equal(rocketId, dto!.RocketId);
        Assert.Equal("Venus", dto.Source);
        Assert.Equal("Jupiter", dto.Destination);
    }

    private record RocketMessageDto(string Source, string Destination, string RocketId, DateTimeOffset LaunchTime);
}
