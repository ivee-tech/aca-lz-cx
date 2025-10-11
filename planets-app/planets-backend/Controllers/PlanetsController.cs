using Microsoft.AspNetCore.Mvc;
using Planets.Api.Data;
using Planets.Api.Models;

namespace Planets.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Route("[controller]")]
[Route("planets")] // explicit for clarity
public class PlanetsController(IPlanetRepository repository) : ControllerBase
{
    [HttpGet]
    public ActionResult<IEnumerable<Planet>> GetAll() => Ok(repository.GetAll());

    [HttpGet("{id:int}")]
    public ActionResult<Planet> GetById(int id)
    {
        var planet = repository.GetById(id);
        return planet is null ? NotFound() : Ok(planet);
    }
}
