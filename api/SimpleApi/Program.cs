using System.Reflection;
using Microsoft.AspNetCore.OpenApi;

var builder = WebApplication.CreateBuilder(args);

// Add services
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(o =>
{
    // Basic metadata
    o.SwaggerDoc("v1", new() { Title = "SimpleApi", Version = "v1" });
    // Include XML comments if generated
    var xmlFile = $"{Assembly.GetExecutingAssembly().GetName().Name}.xml";
    var xmlPath = Path.Combine(AppContext.BaseDirectory, xmlFile);
    if (File.Exists(xmlPath))
    {
        o.IncludeXmlComments(xmlPath);
    }
});

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// Health endpoint (Kubernetes/App Service friendly)
app.MapGet("/healthz", () => Results.Ok("OK"))
   .WithName("Health")
   .WithTags("System");

// Simple greeting
app.MapGet("/api/hello", () => Results.Ok(new ApiMessage("Hello from SimpleApi")))
   .WithName("Hello")
   .WithTags("Demo")
   .WithOpenApi();

// Current UTC time
app.MapGet("/api/time", () => Results.Ok(new { utc = DateTime.UtcNow, machine = Environment.MachineName }))
   .WithName("Time")
   .WithTags("Demo")
   .WithOpenApi();

// Echo payload back
app.MapPost("/api/echo", (EchoRequest body) =>
    Results.Ok(new EchoResponse(body.Text, body.Number, DateTime.UtcNow)))
   .WithName("Echo")
   .WithTags("Demo")
   .WithOpenApi();

app.Run();
