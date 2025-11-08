using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.Json;

namespace Planets.Api.Models;

public sealed record AsteroidFeedResult(DateOnly Date, int TotalCount, IReadOnlyList<AsteroidSummary> Asteroids)
{
    public static AsteroidFeedResult FromJson(string json, DateOnly date)
    {
        ArgumentNullException.ThrowIfNull(json);

        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;

        var totalCount = root.TryGetProperty("element_count", out var totalElement) &&
                         totalElement.TryGetInt32(out var total)
            ? total
            : 0;

        var dateKey = date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        var asteroids = new List<AsteroidSummary>();
        if (root.TryGetProperty("near_earth_objects", out var neoElement) &&
            neoElement.ValueKind == JsonValueKind.Object &&
            neoElement.TryGetProperty(dateKey, out var dayArray) &&
            dayArray.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in dayArray.EnumerateArray())
            {
                var id = item.TryGetProperty("id", out var idElement)
                    ? idElement.GetString() ?? string.Empty
                    : string.Empty;
                var name = item.TryGetProperty("name", out var nameElement)
                    ? nameElement.GetString() ?? id
                    : id;
                var referenceUrl = item.TryGetProperty("nasa_jpl_url", out var urlElement)
                    ? urlElement.GetString() ?? string.Empty
                    : string.Empty;
                var hazardous = item.TryGetProperty("is_potentially_hazardous_asteroid", out var hazardousElement) &&
                                hazardousElement.ValueKind is JsonValueKind.True or JsonValueKind.False &&
                                hazardousElement.GetBoolean();

                double diameterKm = 0;
                if (item.TryGetProperty("estimated_diameter", out var diameterElement) &&
                    diameterElement.ValueKind == JsonValueKind.Object &&
                    diameterElement.TryGetProperty("kilometers", out var kilometersElement) &&
                    kilometersElement.ValueKind == JsonValueKind.Object &&
                    kilometersElement.TryGetProperty("estimated_diameter_max", out var diameterMaxElement) &&
                    diameterMaxElement.TryGetDouble(out var km))
                {
                    diameterKm = km;
                }

                double missDistanceKm = 0;
                if (item.TryGetProperty("close_approach_data", out var closeApproachArray) &&
                    closeApproachArray.ValueKind == JsonValueKind.Array)
                {
                    foreach (var approach in closeApproachArray.EnumerateArray())
                    {
                        if (approach.TryGetProperty("miss_distance", out var missDistanceElement) &&
                            missDistanceElement.ValueKind == JsonValueKind.Object &&
                            missDistanceElement.TryGetProperty("kilometers", out var missDistanceKmElement) &&
                            double.TryParse(missDistanceKmElement.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var missKm))
                        {
                            missDistanceKm = missKm;
                            break;
                        }
                    }
                }

                asteroids.Add(new AsteroidSummary(id, name, diameterKm, missDistanceKm, hazardous, referenceUrl));
            }
        }

        return new AsteroidFeedResult(date, totalCount, asteroids);
    }
}

public sealed record AsteroidSummary(
    string Id,
    string Name,
    double EstimatedMaxDiameterKm,
    double ClosestApproachDistanceKm,
    bool IsPotentiallyHazardous,
    string ReferenceUrl);
