using System.Net;
using System.Net.Http.Json;
using Planets.Api.Models;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace Planets.Api.Tests;

public class PlanetEndpointsTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public PlanetEndpointsTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task GetAll_ReturnsEightPlanets()
    {
        var planets = await _client.GetFromJsonAsync<List<Planet>>("/api/planets");
        Assert.NotNull(planets);
        Assert.Equal(8, planets!.Count);
    }

    [Fact]
    public async Task GetById_ReturnsNotFound_ForInvalidId()
    {
        var response = await _client.GetAsync("/api/planets/999");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }
}
