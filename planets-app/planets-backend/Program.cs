using Planets.Api.Data;
using Planets.Api.Models;
using System.Text.Json;
using Azure.Messaging.ServiceBus;
using System.Collections.Concurrent;
using System.Threading.Channels;
using Microsoft.AspNetCore.Mvc; // For [FromServices]

var builder = WebApplication.CreateBuilder(args);

// Decide repository provider (InMemory or Sql) via config (appsettings or env: PlanetRepository__Provider)
var provider = builder.Configuration.GetSection("PlanetRepository")?["Provider"] ?? "InMemory";
Console.WriteLine($"[Planets] Configured IPlanetRepository provider: {provider}.");
if (string.Equals(provider, "Sql", StringComparison.OrdinalIgnoreCase))
{
    builder.Services.AddSingleton<SqlConnectionFactory>();
    builder.Services.AddSingleton<IPlanetRepository, SqlPlanetRepository>();
    builder.Services.AddHostedService<PlanetDbInitializer>(); // ensure schema + seed
}
else
{
    builder.Services.AddSingleton<IPlanetRepository, InMemoryPlanetRepository>();
}
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
// Using minimal APIs instead of MVC controllers for uniform style
builder.Services.ConfigureHttpJsonOptions(o =>
{
    o.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
});
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", p => p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod());
});

// ---------------- Rocket / Service Bus infrastructure ----------------
// Always register RocketMessageDispatcher so local/dev & tests can use in-memory publish endpoint.
builder.Services.AddSingleton<RocketMessageDispatcher>();
// Config expected via appsettings or environment variables:
//   ServiceBus:QueueName (env: ServiceBus__QueueName) default: rocket-messages
//   ServiceBus:ConnectionString (or env: SERVICEBUS_CONNECTION_STRING) *recommended to use env*
var sbSection = builder.Configuration.GetSection("ServiceBus");
var queueName = sbSection["QueueName"] ?? Environment.GetEnvironmentVariable("SERVICEBUS_QUEUE") ?? "rocket-messages";
var connectionString = sbSection["ConnectionString"] ?? Environment.GetEnvironmentVariable("SERVICEBUS_CONNECTION_STRING");
if (string.IsNullOrWhiteSpace(connectionString))
{
    Console.WriteLine("[Rocket] SERVICEBUS_CONNECTION_STRING not set – running in local in-memory mode.");
}
else
{
    builder.Services.AddSingleton(sp => new ServiceBusClient(connectionString));
    builder.Services.AddHostedService(sp => new ServiceBusRocketListener(
        sp.GetRequiredService<ServiceBusClient>(),
        queueName,
        sp.GetRequiredService<RocketMessageDispatcher>()));
}
// ----------------------------------------------------------------------

var app = builder.Build();

// Configure middleware
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// app.UseHttpsRedirection(); // Disabled for simpler local mixed-content when serving static frontend via file://

app.UseCors("AllowAll");

// Planets endpoints (minimal API style)
var planets = app.MapGroup("/api/planets").WithTags("Planets");
planets.MapGet("/", ([FromServices] ILogger<Program> logger, IPlanetRepository repo) =>
    {
        var providerName = repo.GetType().Name;
        logger.LogInformation("GetPlanets executing with provider {Provider}", providerName);
        return Results.Ok(repo.GetAll());
    })
    .WithName("GetPlanets");
planets.MapGet("/{id:int}", ([FromServices] ILogger<Program> logger, IPlanetRepository repo, int id) =>
    {
        var providerName = repo.GetType().Name;
        var planet = repo.GetById(id);
        if (planet is null)
        {
            logger.LogWarning("GetPlanetById({PlanetId}) using provider {Provider} returned not found", id, providerName);
            return Results.NotFound();
        }

        logger.LogInformation("GetPlanetById({PlanetId}) executing with provider {Provider}", id, providerName);
        return Results.Ok(planet);
    })
    .WithName("GetPlanetById");

// Health endpoint (minimal API)
app.MapGet("/health", () => Results.Ok(new { status = "ok", timestamp = DateTimeOffset.UtcNow }))
    .WithName("Health");

// SSE endpoint for streaming rocket messages to frontend
app.MapGet("/api/rockets/stream", async (HttpContext ctx, [FromServices] RocketMessageDispatcher dispatcher) =>
{
    ctx.Response.Headers.CacheControl = "no-cache";
    ctx.Response.Headers["Content-Type"] = "text/event-stream";
    // Send an initial comment to flush headers so clients can start reading immediately.
    await ctx.Response.WriteAsync(": stream-open\n\n");
    await ctx.Response.Body.FlushAsync();
    var subscription = dispatcher.Subscribe();
    try
    {
        await foreach (var msg in subscription.ReadAllAsync(ctx.RequestAborted))
        {
            var json = JsonSerializer.Serialize(msg, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
            await ctx.Response.WriteAsync($"data: {json}\n\n");
            await ctx.Response.Body.FlushAsync();
        }
    }
    finally
    {
        dispatcher.Unsubscribe(subscription); 
    }
});

// Simple latest message endpoint (optional polling fallback)
app.MapGet("/api/rockets/latest", ([FromServices] RocketMessageDispatcher dispatcher) =>
    dispatcher.Latest is RocketMessage last ? Results.Ok(last) : Results.NoContent());

// Local/dev publish endpoint (no auth; consider securing or disabling in production)
app.MapPost("/api/rockets/publish", ([FromServices] RocketMessageDispatcher dispatcher, RocketMessage msg) =>
{
    var enriched = msg with { LaunchTime = msg.LaunchTime == default ? DateTimeOffset.UtcNow : msg.LaunchTime };
    dispatcher.Publish(enriched);
    return Results.Accepted(value: enriched);
}).WithDescription("Publish a rocket message to all SSE subscribers (local/dev/testing).");

app.Run();

// Make Program visible for tests
public partial class Program { }

// Rocket message contract
public record RocketMessage(string Source, string Destination, string RocketId, DateTimeOffset LaunchTime);

// Dispatcher maintains fan-out channels for SSE subscribers
public class RocketMessageDispatcher
{
    private readonly ConcurrentDictionary<Guid, Channel<RocketMessage>> _subscribers = new();
    public RocketMessage? Latest { get; private set; }

    public ChannelReader<RocketMessage> Subscribe()
    {
        var channel = Channel.CreateUnbounded<RocketMessage>(new UnboundedChannelOptions { SingleReader = true, SingleWriter = false });
        _subscribers[Guid.NewGuid()] = channel;
        return channel.Reader;
    }

    public void Unsubscribe(ChannelReader<RocketMessage> reader)
    {
        var kvp = _subscribers.FirstOrDefault(kv => kv.Value.Reader == reader);
        if (!kvp.Equals(default(KeyValuePair<Guid, Channel<RocketMessage>>)))
        {
            _subscribers.TryRemove(kvp.Key, out _);
        }
    }

    public void Publish(RocketMessage msg)
    {
        Latest = msg;
        foreach (var ch in _subscribers.Values)
        {
            ch.Writer.TryWrite(msg);
        }
    }
}

// Hosted service reading Service Bus queue and publishing messages
public class ServiceBusRocketListener : BackgroundService
{
    private readonly ServiceBusClient _client;
    private readonly string _queue;
    private readonly RocketMessageDispatcher _dispatcher;
    private ServiceBusProcessor? _processor;
    public ServiceBusRocketListener(ServiceBusClient client, string queue, RocketMessageDispatcher dispatcher)
    { _client = client; _queue = queue; _dispatcher = dispatcher; }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _processor = _client.CreateProcessor(_queue, new ServiceBusProcessorOptions
        {
            AutoCompleteMessages = false,
            MaxConcurrentCalls = 1
        });
        _processor.ProcessMessageAsync += OnMessage;
        _processor.ProcessErrorAsync += args =>
        {
            Console.WriteLine($"[Rocket Listener] Error: {args.Exception.Message}");
            return Task.CompletedTask;
        };
        await _processor.StartProcessingAsync(stoppingToken);
        Console.WriteLine($"[Rocket Listener] Listening on queue '{_queue}'.");
        // Keep running until cancellation
        await Task.Delay(Timeout.Infinite, stoppingToken).ContinueWith(_ => { });
    }

    private async Task OnMessage(ProcessMessageEventArgs args)
    {
        try
        {
            var body = args.Message.Body.ToString();
            var msg = JsonSerializer.Deserialize<RocketMessage>(body, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
            if (msg is not null)
            {
                _dispatcher.Publish(msg);
                Console.WriteLine($"[Rocket Listener] Message {msg.RocketId} {msg.Source}->{msg.Destination}");
            }
            await args.CompleteMessageAsync(args.Message);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Rocket Listener] Failed to process message: {ex.Message}");
        }
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        if (_processor != null)
        {
            await _processor.StopProcessingAsync(cancellationToken);
            await _processor.DisposeAsync();
        }
        await base.StopAsync(cancellationToken);
    }
}
