using Planets.Api.Data;
using Planets.Api.Models;
using System.Text.Json;
using Azure.Messaging.ServiceBus;
using System.Collections.Concurrent;
using System.Threading.Channels;
using Microsoft.AspNetCore.Mvc; // For [FromServices]
using Azure.Identity;
using Azure.Core;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Hosting;

var builder = WebApplication.CreateBuilder(args);

// Decide repository provider (InMemory or Sql) via config (appsettings or env: PlanetRepository__Provider)
var configuredProvider = builder.Configuration["PlanetRepository:Provider"];
var provider = string.IsNullOrWhiteSpace(configuredProvider) ? "InMemory" : configuredProvider.Trim();
Console.WriteLine($"[Planets] IPlanetRepository provider resolved to '{provider}' (raw value: '{configuredProvider ?? "<null>"}').");
if (!string.Equals(provider, "InMemory", StringComparison.OrdinalIgnoreCase) &&
    !string.Equals(provider, "Sql", StringComparison.OrdinalIgnoreCase))
{
    Console.WriteLine($"[Planets] WARNING: Unknown provider '{provider}'. Falling back to InMemory.");
}
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
// Always register in-memory store so local/dev & tests can use in-memory publish endpoint.
builder.Services.AddSingleton<InMemoryRocketMessageStore>();
// Config expected via appsettings or matching env vars (e.g., ServiceBus__QueueName)
var sbSection = builder.Configuration.GetSection("ServiceBus");
var queueName = sbSection["QueueName"];
var connectionString = sbSection["ConnectionString"];
var fullyQualifiedNamespace = sbSection["FullyQualifiedNamespace"];
var managedIdentityClientId = sbSection["ManagedIdentityClientId"];
var useManagedIdentity = sbSection.GetValue("UseManagedIdentity", false);
if (string.IsNullOrWhiteSpace(queueName))
{
    queueName = "rocket-messages";
}
var usingServiceBus = false;

if (!string.IsNullOrWhiteSpace(connectionString) && !useManagedIdentity)
{
    Console.WriteLine("[Rocket] Service Bus authentication mode: ConnectionString");
    builder.Services.AddSingleton(_ => new ServiceBusClient(connectionString));
    usingServiceBus = true;
}
else if (useManagedIdentity)
{
    if (string.IsNullOrWhiteSpace(fullyQualifiedNamespace))
    {
        Console.WriteLine("[Rocket] Service Bus managed identity enabled but FullyQualifiedNamespace not provided – staying in in-memory mode.");
    }
    else
    {
        Console.WriteLine($"[Rocket] Service Bus authentication mode: ManagedIdentity (namespace '{fullyQualifiedNamespace}')");
        if (!string.IsNullOrWhiteSpace(connectionString))
        {
            Console.WriteLine("[Rocket] Connection string supplied but UseManagedIdentity=true – ignoring connection string.");
        }
        builder.Services.AddSingleton<TokenCredential>(_ =>
        {
            var options = new DefaultAzureCredentialOptions();
            if (!string.IsNullOrWhiteSpace(managedIdentityClientId))
            {
                options.ManagedIdentityClientId = managedIdentityClientId;
                Console.WriteLine($"[Rocket] Managed identity client id: {managedIdentityClientId}.");
            }
            return new DefaultAzureCredential(options);
        });
        builder.Services.AddSingleton(sp =>
        {
            var credential = sp.GetRequiredService<TokenCredential>();
            return new ServiceBusClient(fullyQualifiedNamespace, credential);
        });
        usingServiceBus = true;
    }
}
else
{
    Console.WriteLine("[Rocket] Service Bus authentication mode: InMemory (no remote queue configured).");
}

if (usingServiceBus)
{
    Console.WriteLine($"[Rocket] Service Bus queue name: '{queueName}'.");
    builder.Services.AddSingleton(sp => sp.GetRequiredService<ServiceBusClient>().CreateSender(queueName));
    builder.Services.AddSingleton<IRocketPublisher, ServiceBusRocketPublisher>();
    builder.Services.AddSingleton<ServiceBusRocketMessageStore>(sp =>
    {
        var inner = sp.GetRequiredService<InMemoryRocketMessageStore>();
        var client = sp.GetRequiredService<ServiceBusClient>();
        var logger = sp.GetRequiredService<ILogger<ServiceBusRocketMessageStore>>();
        return new ServiceBusRocketMessageStore(inner, client, queueName, logger);
    });
    builder.Services.AddSingleton<IRocketMessageStore>(sp => sp.GetRequiredService<ServiceBusRocketMessageStore>());
    builder.Services.AddHostedService(sp => sp.GetRequiredService<ServiceBusRocketMessageStore>());
}
else
{
    builder.Services.AddSingleton<IRocketPublisher, InMemoryRocketPublisher>();
    builder.Services.AddSingleton<IRocketMessageStore>(sp => sp.GetRequiredService<InMemoryRocketMessageStore>());
}
// ----------------------------------------------------------------------

var app = builder.Build();

// Emit startup diagnostics for rocket publisher selection
try
{
    var resolvedPublisher = app.Services.GetRequiredService<IRocketPublisher>();
    Console.WriteLine($"[Rocket] Publisher implementation resolved: {resolvedPublisher.GetType().Name} (ServiceBusEnabled={usingServiceBus}).");
}
catch (Exception ex)
{
    Console.WriteLine($"[Rocket] Failed to resolve IRocketPublisher during startup diagnostics: {ex.Message}");
}

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
app.MapGet("/api/rockets/stream", async (HttpContext ctx, [FromServices] IRocketMessageStore store) =>
{
    ctx.Response.Headers.CacheControl = "no-cache";
    ctx.Response.Headers["Content-Type"] = "text/event-stream";
    await ctx.Response.WriteAsync(": stream-open\n\n");
    await ctx.Response.Body.FlushAsync();

    var reader = store.Subscribe();
    var cancellation = ctx.RequestAborted;
    var jsonOptions = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    var heartbeatInterval = TimeSpan.FromSeconds(15);
    var readTask = reader.ReadAsync(cancellation).AsTask();
    var heartbeatTask = Task.Delay(heartbeatInterval, cancellation);

    try
    {
        while (!cancellation.IsCancellationRequested)
        {
            var completed = await Task.WhenAny(readTask, heartbeatTask);
            if (completed == readTask)
            {
                RocketMessage msg;
                try
                {
                    msg = await readTask;
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (ChannelClosedException)
                {
                    break;
                }

                var json = JsonSerializer.Serialize(msg, jsonOptions);
                await ctx.Response.WriteAsync($"data: {json}\n\n");
                await ctx.Response.Body.FlushAsync();

                readTask = reader.ReadAsync(cancellation).AsTask();
            }
            else
            {
                if (!heartbeatTask.IsCanceled && !heartbeatTask.IsFaulted)
                {
                    await ctx.Response.WriteAsync(": keep-alive\n\n");
                    await ctx.Response.Body.FlushAsync();
                }
                heartbeatTask = Task.Delay(heartbeatInterval, cancellation);
            }
        }
    }
    finally
    {
        store.Unsubscribe(reader);
    }
});

// Simple latest message endpoint (optional polling fallback)
app.MapGet("/api/rockets/latest", ([FromServices] IRocketMessageStore store) =>
    store.Latest is RocketMessage last ? Results.Ok(last) : Results.NoContent());

// Local/dev publish endpoint (no auth; consider securing or disabling in production)
app.MapPost("/api/rockets/publish", async ([FromServices] IRocketPublisher publisher, RocketMessage msg, CancellationToken cancellationToken) =>
{
    var enriched = msg with { LaunchTime = msg.LaunchTime == default ? DateTimeOffset.UtcNow : msg.LaunchTime };
    await publisher.PublishAsync(enriched, cancellationToken);
    return Results.Accepted(value: enriched);
}).WithDescription("Publish a rocket message to all SSE subscribers (local/dev/testing).");

app.Run();

// Make Program visible for tests
public partial class Program { }

// Rocket message contract
public record RocketMessage(string Source, string Destination, string RocketId, DateTimeOffset LaunchTime);

public interface IRocketMessageStore
{
    ChannelReader<RocketMessage> Subscribe();
    void Unsubscribe(ChannelReader<RocketMessage> reader);
    RocketMessage? Latest { get; }
    void Publish(RocketMessage message);
}

// In-memory message store maintains fan-out channels for SSE subscribers
public class InMemoryRocketMessageStore : IRocketMessageStore
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

public interface IRocketPublisher
{
    Task PublishAsync(RocketMessage message, CancellationToken cancellationToken = default);
}

public class InMemoryRocketPublisher : IRocketPublisher
{
    private readonly IRocketMessageStore _store;
    private readonly ILogger<InMemoryRocketPublisher> _logger;

    public InMemoryRocketPublisher(IRocketMessageStore store, ILogger<InMemoryRocketPublisher> logger)
    {
        _store = store;
        _logger = logger;
    }

    public Task PublishAsync(RocketMessage message, CancellationToken cancellationToken = default)
    {
        _store.Publish(message);
        _logger.LogInformation("Dispatched rocket {RocketId} {Source}->{Destination} via in-memory publisher.", message.RocketId, message.Source, message.Destination);
        return Task.CompletedTask;
    }
}

public class ServiceBusRocketPublisher : IRocketPublisher
{
    internal static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    private readonly ServiceBusSender _sender;
    private readonly ILogger<ServiceBusRocketPublisher> _logger;

    public ServiceBusRocketPublisher(ServiceBusSender sender, ILogger<ServiceBusRocketPublisher> logger)
    {
        _sender = sender;
        _logger = logger;
    }

    public async Task PublishAsync(RocketMessage message, CancellationToken cancellationToken = default)
    {
        try
        {
            var payload = JsonSerializer.Serialize(message, JsonOptions);
            var serviceBusMessage = new ServiceBusMessage(BinaryData.FromString(payload))
            {
                ContentType = "application/json"
            };
            serviceBusMessage.ApplicationProperties["rocketId"] = message.RocketId;
            serviceBusMessage.ApplicationProperties["source"] = message.Source;
            serviceBusMessage.ApplicationProperties["destination"] = message.Destination;

            await _sender.SendMessageAsync(serviceBusMessage, cancellationToken);
            _logger.LogInformation("Queued rocket {RocketId} {Source}->{Destination} for processing via Service Bus.", message.RocketId, message.Source, message.Destination);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to enqueue rocket {RocketId} for Service Bus processing.", message.RocketId);
            throw;
        }
    }
}

public class ServiceBusRocketMessageStore : IRocketMessageStore, IHostedService
{
    private readonly InMemoryRocketMessageStore _inner;
    private readonly ServiceBusClient _client;
    private readonly string _queue;
    private readonly ILogger<ServiceBusRocketMessageStore> _logger;
    private ServiceBusProcessor? _processor;

    public ServiceBusRocketMessageStore(InMemoryRocketMessageStore inner, ServiceBusClient client, string queue, ILogger<ServiceBusRocketMessageStore> logger)
    {
        _inner = inner;
        _client = client;
        _queue = queue;
        _logger = logger;
    }

    public RocketMessage? Latest => _inner.Latest;

    public ChannelReader<RocketMessage> Subscribe() => _inner.Subscribe();

    public void Unsubscribe(ChannelReader<RocketMessage> reader) => _inner.Unsubscribe(reader);

    public void Publish(RocketMessage message) => _inner.Publish(message);

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        _processor = _client.CreateProcessor(_queue, new ServiceBusProcessorOptions
        {
            AutoCompleteMessages = false,
            MaxConcurrentCalls = 1
        });

        _processor.ProcessMessageAsync += OnMessageAsync;
        _processor.ProcessErrorAsync += OnErrorAsync;

        await _processor.StartProcessingAsync(cancellationToken);
        _logger.LogInformation("[Rocket] Listening on Service Bus queue {Queue}", _queue);
    }

    private async Task OnMessageAsync(ProcessMessageEventArgs args)
    {
        try
        {
            var body = args.Message.Body.ToString();
            var msg = JsonSerializer.Deserialize<RocketMessage>(body, ServiceBusRocketPublisher.JsonOptions);
            if (msg is not null)
            {
                _inner.Publish(msg);
                _logger.LogInformation("[Rocket] Message {RocketId} {Source}->{Destination}", msg.RocketId, msg.Source, msg.Destination);
            }
            await args.CompleteMessageAsync(args.Message);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[Rocket] Failed to process Service Bus message");
        }
    }

    private Task OnErrorAsync(ProcessErrorEventArgs args)
    {
        _logger.LogError(args.Exception, "[Rocket] Service Bus processor error from entity {EntityPath}", args.EntityPath);
        return Task.CompletedTask;
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        if (_processor != null)
        {
            await _processor.StopProcessingAsync(cancellationToken);
            await _processor.DisposeAsync();
            _processor = null;
        }
    }
}
