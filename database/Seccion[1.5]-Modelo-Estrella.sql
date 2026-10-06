CREATE DATABASE DW_DataSalud; 
GO 
 
USE DW_DataSalud; 
GO 
 
CREATE TABLE DimFecha ( 
    FechaKey INT PRIMARY KEY, 
    Fecha DATE NOT NULL, 
    Dia INT NOT NULL, 
    NombreDia VARCHAR(20) NOT NULL, 
    Mes INT NOT NULL, 
    NombreMes VARCHAR(20) NOT NULL, 
    Trimestre INT NOT NULL, 
    Anio INT NOT NULL 
); 
GO 
 
CREATE TABLE DimUbicacion ( 
    UbicacionKey INT IDENTITY(1,1) PRIMARY KEY, 
    Ubigeo VARCHAR(6) NOT NULL UNIQUE, 
    Departamento VARCHAR(100) NOT NULL, 
    Provincia VARCHAR(100) NOT NULL, 
    Distrito VARCHAR(100) NOT NULL 
); 
GO 
 
CREATE TABLE DimVacuna ( 
    VacunaKey INT IDENTITY(1,1) PRIMARY KEY, 
    TipoVacuna VARCHAR(100) NOT NULL 
); 
GO 
 
CREATE TABLE DimDemografia ( 
    DemografiaKey INT IDENTITY(1,1) PRIMARY KEY, 
    Sexo CHAR(1) NOT NULL, 
    GrupoEtario VARCHAR(50) NOT NULL 
); 
GO 
 
CREATE TABLE DimIPRESS ( 
    IPRESSKey INT IDENTITY(1,1) PRIMARY KEY, 
    CodigoRenipress VARCHAR(20) NOT NULL UNIQUE, 
    NombreIPRESS VARCHAR(200) NOT NULL, 
    Departamento VARCHAR(100), 
    Provincia VARCHAR(100), 
    Distrito VARCHAR(100), 
    TipoEstablecimiento VARCHAR(100), 
    CategoriaIPRESS VARCHAR(50), 
    EstadoIPRESS VARCHAR(50), 
    Ubigeo VARCHAR(6) 
); 
GO 
 
CREATE TABLE FactVacunacion ( 
    VacunacionKey BIGINT IDENTITY(1,1) PRIMARY KEY, 
 
    FechaKey INT NOT NULL, 
    UbicacionKey INT NOT NULL, 
    VacunaKey INT NOT NULL, 
    DemografiaKey INT NOT NULL, 
    IPRESSKey INT NULL, 
 
    DosisAplicadas INT NOT NULL, 
 
    CONSTRAINT FK_Fact_Fecha 
        FOREIGN KEY (FechaKey) 
        REFERENCES DimFecha(FechaKey), 
 
    CONSTRAINT FK_Fact_Ubicacion 
        FOREIGN KEY (UbicacionKey) 
        REFERENCES DimUbicacion(UbicacionKey), 
 
    CONSTRAINT FK_Fact_Vacuna 
        FOREIGN KEY (VacunaKey) 
        REFERENCES DimVacuna(VacunaKey), 
 
    CONSTRAINT FK_Fact_Demografia 
        FOREIGN KEY (DemografiaKey) 
        REFERENCES DimDemografia(DemografiaKey), 
 
    CONSTRAINT FK_Fact_IPRESS 
        FOREIGN KEY (IPRESSKey) 
        REFERENCES DimIPRESS(IPRESSKey), 
 
    CONSTRAINT CK_Fact_Dosis 
        CHECK (DosisAplicadas > 0) 
); 
GO 
 
CREATE INDEX IX_FactVacunacion_Fecha 
ON FactVacunacion(FechaKey); 
GO 
 
CREATE INDEX IX_FactVacunacion_Ubicacion 
ON FactVacunacion(UbicacionKey); 
GO 
 
CREATE INDEX IX_FactVacunacion_Vacuna 
ON FactVacunacion(VacunaKey); 
GO 
 
CREATE INDEX IX_FactVacunacion_Demografia 
ON FactVacunacion(DemografiaKey); 
GO 
 
CREATE INDEX IX_FactVacunacion_IPRESS 
ON FactVacunacion(IPRESSKey); 
GO
