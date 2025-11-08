namespace Planets.Api.Options;

public sealed class NasaNeoFeedOptions
{
    /// <summary>
    ///     Name of the Dapr binding component that proxies calls to the NASA Neo Feed API.
    /// </summary>
    public string ComponentName { get; set; } = "nasa-neo-feed";

    /// <summary>
    ///     API key issued by NASA. Leave empty to rely on environment configuration.
    /// </summary>
    public string? ApiKey { get; set; } = "DEMO_KEY";

    /// <summary>
    ///     Relative path for the feed endpoint.
    /// </summary>
    public string Path { get; set; } = "/neo/rest/v1/feed";

    /// <summary>
    ///     Whether to request the detailed response variant.
    /// </summary>
    public bool Detailed { get; set; }
}
