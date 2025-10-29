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
        var csb = new SqlConnectionStringBuilder(_connectionString);
        var authMethod = csb.Authentication;
    var hasAuthKeyword = authMethod != SqlAuthenticationMethod.NotSpecified;
    bool shouldInjectManagedIdentityToken = _forceManagedIdentity && !hasAuthKeyword;

        var conn = new SqlConnection(csb.ConnectionString);

        if (shouldInjectManagedIdentityToken)
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
        else if (hasAuthKeyword)
        {
            _logger.LogInformation("Connection string specifies Authentication={Authentication}; relying on SqlClient to handle identity.", authMethod);
        }
        // else rely on SqlClient's internal flow or SQL auth via connection string.

        await conn.OpenAsync(ct);
        return conn;
    }
}
