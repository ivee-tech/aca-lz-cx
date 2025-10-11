using System.Text.Json;
using Azure.Messaging.ServiceBus;

// Console app to enqueue rocket launch messages.
// Required env vars:
//   SERVICEBUS_CONNECTION_STRING : connection string with Send rights
// Optional:
//   SERVICEBUS_QUEUE : queue name (default: rocket-messages)
// Args: [count] [intervalMs]
//   count: number of messages to send (default infinite)
//   intervalMs: delay between messages (default 4000)

var connectionString = Environment.GetEnvironmentVariable("SERVICEBUS_CONNECTION_STRING")
    ?? throw new InvalidOperationException("SERVICEBUS_CONNECTION_STRING not set");
var queueName = Environment.GetEnvironmentVariable("SERVICEBUS_QUEUE") ?? "rocket-messages";

int? count = null;
if (args.Length > 0 && int.TryParse(args[0], out var parsedCount)) count = parsedCount;
int interval = 4000;
if (args.Length > 1 && int.TryParse(args[1], out var parsedInterval)) interval = parsedInterval;

var destinations = new[] { "Mercury", "Venus", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune" };
var random = new Random();

Console.WriteLine($"Rocket client starting. Queue={queueName} Count={(count?.ToString() ?? "∞")} Interval={interval}ms");
Console.WriteLine("Press Ctrl+C to exit.");

// ServiceBusClient implements IAsyncDisposable (not IDisposable) so use await using
await using var client = new ServiceBusClient(connectionString);
ServiceBusSender sender = client.CreateSender(queueName);

int sent = 0;
while (!Console.KeyAvailable)
{
    if (count.HasValue && sent >= count) break;
    var destination = destinations[random.Next(destinations.Length)];
    var rocket = new RocketMessage(
        Source: "Earth",
        Destination: destination,
        RocketId: Guid.NewGuid().ToString("N").Substring(0, 10),
        LaunchTime: DateTimeOffset.UtcNow
    );
    var json = JsonSerializer.Serialize(rocket, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
    var message = new ServiceBusMessage(json)
    {
        ContentType = "application/json"
    };
    await sender.SendMessageAsync(message);
    sent++;
    Console.WriteLine($"Sent {rocket.RocketId} Earth -> {destination}");
    await Task.Delay(interval);
}

Console.WriteLine("Done.");

public record RocketMessage(string Source, string Destination, string RocketId, DateTimeOffset LaunchTime);
