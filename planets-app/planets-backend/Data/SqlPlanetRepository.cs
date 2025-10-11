using System.Data;
using Microsoft.Data.SqlClient;
using Planets.Api.Models;
using Polly;

namespace Planets.Api.Data;

/// <summary>
/// SQL-backed implementation of <see cref="IPlanetRepository"/> targeting Azure SQL / SQL Server.
/// Read-only operations matching current interface requirements (GetAll, GetById).
/// </summary>
public class SqlPlanetRepository : IPlanetRepository
{
    private readonly SqlConnectionFactory _factory;
    private readonly ILogger<SqlPlanetRepository> _logger;
    private readonly IAsyncPolicy _retryPolicy;

    public SqlPlanetRepository(SqlConnectionFactory factory, ILogger<SqlPlanetRepository> logger)
    {
        _factory = factory;
        _logger = logger;

        // Basic transient-fault retry (can be refined with dedicated Polly.Contrib resilience strategies).
        _retryPolicy = Polly.Policy
            .Handle<SqlException>(IsTransient)
            .Or<TimeoutException>()
            .WaitAndRetryAsync(5, attempt => TimeSpan.FromMilliseconds(100 * Math.Pow(2, attempt)),
                (ex, delay, attempt, ctx) =>
                {
                    _logger.LogWarning(ex, "Transient DB error on attempt {Attempt}. Retrying after {Delay}.", attempt, delay);
                });
    }

    public IEnumerable<Planet> GetAll()
    {
        return GetAllAsync().GetAwaiter().GetResult();
    }

    public Planet? GetById(int id)
    {
        return GetByIdAsync(id).GetAwaiter().GetResult();
    }

    private async Task<IEnumerable<Planet>> GetAllAsync()
    {
        const string sql = @"SELECT Id, Name, Size, Distance, Speed, RotationSpeed, TextureUrl FROM dbo.Planets ORDER BY Id";
        var results = new List<Planet>();
        await _retryPolicy.ExecuteAsync(async () =>
        {
            await using var conn = await _factory.CreateOpenAsync();
            await using var cmd = new SqlCommand(sql, conn) { CommandType = CommandType.Text };
            cmd.CommandTimeout = 10;
            await using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                results.Add(new Planet(
                    reader.GetInt32(0),
                    reader.GetString(1),
                    Convert.ToDouble(reader.GetDecimal(2)),
                    Convert.ToDouble(reader.GetDecimal(3)),
                    Convert.ToDouble(reader.GetDecimal(4)),
                    Convert.ToDouble(reader.GetDecimal(5)),
                    reader.GetString(6)
                ));
            }
        });
        return results;
    }

    private async Task<Planet?> GetByIdAsync(int id)
    {
        const string sql = @"SELECT Id, Name, Size, Distance, Speed, RotationSpeed, TextureUrl FROM dbo.Planets WHERE Id = @id";
        Planet? planet = null;
        await _retryPolicy.ExecuteAsync(async () =>
        {
            await using var conn = await _factory.CreateOpenAsync();
            await using var cmd = new SqlCommand(sql, conn) { CommandType = CommandType.Text };
            cmd.Parameters.Add(new SqlParameter("@id", SqlDbType.Int) { Value = id });
            cmd.CommandTimeout = 5;
            await using var reader = await cmd.ExecuteReaderAsync();
            if (await reader.ReadAsync())
            {
                planet = new Planet(
                    reader.GetInt32(0),
                    reader.GetString(1),
                    Convert.ToDouble(reader.GetDecimal(2)),
                    Convert.ToDouble(reader.GetDecimal(3)),
                    Convert.ToDouble(reader.GetDecimal(4)),
                    Convert.ToDouble(reader.GetDecimal(5)),
                    reader.GetString(6)
                );
            }
        });
        return planet;
    }

    private static bool IsTransient(SqlException ex)
    {
        // Basic list of retriable error numbers (can be extended with Azure SQL transient errors).
        int[] transientErrorNumbers = [4060, 10928, 10929, 40197, 40501, 40613, 49918, 49919, 49920];
        return ex.Errors.Cast<SqlError>().Any(e => transientErrorNumbers.Contains(e.Number));
    }
}
