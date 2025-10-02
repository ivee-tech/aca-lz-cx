// Record models used by the API endpoints
public record ApiMessage(string Message);
public record EchoRequest(string? Text, int? Number);
public record EchoResponse(string? Text, int? Number, DateTime ReceivedUtc);
