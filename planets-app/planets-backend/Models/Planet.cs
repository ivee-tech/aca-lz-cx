namespace Planets.Api.Models;

// Planet domain model aligned with frontend expectations.
// Units:
//  - Size: relative to Earth's diameter (=1.0)
//  - Distance: millions of km (values taken as provided by spec)
//  - Speed: arbitrary orbital speed factor used by animation
//  - RotationSpeed: arbitrary rotation speed factor used by animation
public record Planet(
    int Id,
    string Name,
    double Size,
    double Distance,
    double Speed,
    double RotationSpeed,
    string TextureUrl
);
