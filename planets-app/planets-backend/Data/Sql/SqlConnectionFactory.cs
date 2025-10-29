using Azure.Core;
using Azure.Identity;
using Microsoft.Data.SqlClient;

namespace Planets.Api.Data;

/// <summary>
/// Creates <see cref="SqlConnection"/> instances supporting both classic connection strings
/// and Azure Managed Identity (DefaultAzureCredential) token-based auth for Azure SQL.
/// </summary>
public class SqlConnectionFactory
{
    private readonly string _connectionString;
    private readonly bool _forceManagedIdentity;
    private readonly ILogger<SqlConnectionFactory> _logger;
    private readonly TokenCredential _credential;
    private readonly string? _managedIdentityClientId;

    private static readonly string AzureSqlScope = "https://database.windows.net//.default"; // double slash per AAD expectations

    public SqlConnectionFactory(IConfiguration config, ILogger<SqlConnectionFactory> logger)
    {
        _connectionString = config.GetConnectionString("PlanetDb") ?? throw new InvalidOperationException("Connection string 'PlanetDb' not configured.");
        _logger = logger;
        _forceManagedIdentity = config.GetValue("PlanetRepository:UseManagedIdentity", true); // default true for Azure deploys
        _managedIdentityClientId = config["Sql:ManagedIdentityClientId"];

        var credentialOptions = new DefaultAzureCredentialOptions();
        if (!string.IsNullOrWhiteSpace(_managedIdentityClientId))
        {
            credentialOptions.ManagedIdentityClientId = _managedIdentityClientId;
            _logger.LogInformation("SqlConnectionFactory configured with managed identity client id {ClientId}.", _managedIdentityClientId);
        }

        // DefaultAzureCredential will: Managed Identity (in ACA), Environment, Visual Studio/CLI dev tokens.
        _credential = new DefaultAzureCredential(credentialOptions);
    }

    public async Task<SqlConnection> CreateOpenAsync(CancellationToken ct = default)
    {
        // If the connection string already specifies an Authentication keyword let SqlClient handle it.
        var csb = new SqlConnectionStringBuilder(_connectionString);
        bool hasAuthKeyword = _connectionString.Contains("Authentication=", StringComparison.OrdinalIgnoreCase);

        var conn = new SqlConnection(csb.ConnectionString);

        if (!hasAuthKeyword && _forceManagedIdentity)
        {
            // Acquire access token for Azure SQL
            try
            {
                var token = await _credential.GetTokenAsync(new TokenRequestContext([AzureSqlScope]), ct);
                conn.AccessToken = token.Token;
                _logger.LogInformation("Using managed identity access token (expires {ExpiresOn:u}){ClientInfo}.", token.ExpiresOn,
                    string.IsNullOrWhiteSpace(_managedIdentityClientId) ? string.Empty : $" for client {_managedIdentityClientId}");
            }
            catch (AuthenticationFailedException ex)
            {
                _logger.LogError(ex, "Failed to acquire managed identity token for Azure SQL. Ensure the Container App identity has access and the client id (if any) is correct.");
                throw;
            }
        }
        // else rely on SqlClient's internal AAD flow or SQL Auth as provided.

        await conn.OpenAsync(ct);
        return conn;
    }
}
