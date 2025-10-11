using Planets.Api.Models;

namespace Planets.Api.Data;

public class InMemoryPlanetRepository : IPlanetRepository
{
    private readonly List<Planet> _planets;

    public InMemoryPlanetRepository()
    {
        // Seed data aligned with provided spec.
        _planets = new()
        {
            new Planet(1, "Mercury", 0.383, 5.79, 0.08, 0.01, "assets/mercury.jpg"),
            new Planet(2, "Venus", 0.949, 10.82, 0.03, 0.006, "assets/venus.jpg"),
            new Planet(3, "Earth", 1.0, 15.0, 0.02, 0.008, "assets/earth.jpg"),
            new Planet(4, "Mars", 0.532, 22.79, 0.016, 0.012, "assets/mars.jpg"),
            new Planet(5, "Jupiter", 11.21, 77.78, 0.004, 0.014, "assets/jupiter.jpg"),
            new Planet(6, "Saturn", 9.45, 143.37, 0.002, 0.016, "assets/saturn.jpg"),
            new Planet(7, "Uranus", 4.01, 287.1, 0.0008, 0.018, "assets/uranus.jpg"),
            new Planet(8, "Neptune", 3.88, 449.5, 0.0004, 0.02, "assets/neptune.jpg")
        };
    }

    public IEnumerable<Planet> GetAll() => _planets;

    public Planet? GetById(int id) => _planets.FirstOrDefault(p => p.Id == id);
}
