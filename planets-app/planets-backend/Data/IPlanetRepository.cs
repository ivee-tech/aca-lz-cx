using Planets.Api.Models;

namespace Planets.Api.Data;

public interface IPlanetRepository
{
    IEnumerable<Planet> GetAll();
    Planet? GetById(int id);
}
