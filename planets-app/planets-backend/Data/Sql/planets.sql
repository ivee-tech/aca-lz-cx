-- Schema + seed script for Planets table (Azure SQL / SQL Server)
IF OBJECT_ID('dbo.Planets','U') IS NULL
BEGIN
    CREATE TABLE dbo.Planets (
        Id INT NOT NULL PRIMARY KEY,
        Name NVARCHAR(64) NOT NULL,
        Size DECIMAL(10,4) NOT NULL,
        Distance DECIMAL(12,4) NOT NULL,
        Speed DECIMAL(12,6) NOT NULL,
        RotationSpeed DECIMAL(12,6) NOT NULL,
        TextureUrl NVARCHAR(256) NOT NULL
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Planets)
BEGIN
    INSERT INTO dbo.Planets (Id, Name, Size, Distance, Speed, RotationSpeed, TextureUrl) VALUES
    (1,'Mercury',0.383,5.79,0.08,0.01,'assets/mercury.jpg'),
    (2,'Venus',0.949,10.82,0.03,0.006,'assets/venus.jpg'),
    (3,'Earth',1.0,15.0,0.02,0.008,'assets/earth.jpg'),
    (4,'Mars',0.532,22.79,0.016,0.012,'assets/mars.jpg'),
    (5,'Jupiter',11.21,77.78,0.004,0.014,'assets/jupiter.jpg'),
    (6,'Saturn',9.45,143.37,0.002,0.016,'assets/saturn.jpg'),
    (7,'Uranus',4.01,287.1,0.0008,0.018,'assets/uranus.jpg'),
    (8,'Neptune',3.88,449.5,0.0004,0.02,'assets/neptune.jpg');
END
GO

CREATE USER [id-crnascmieoldevaue-AcrPull] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [id-crnascmieoldevaue-AcrPull];
ALTER ROLE db_datawriter ADD MEMBER [id-crnascmieoldevaue-AcrPull];
GO
