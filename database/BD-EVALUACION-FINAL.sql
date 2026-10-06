create database BD_DIRESA_LALIBERTAD
GO
use BD_DIRESA_LALIBERTAD
go

CREATE TABLE Ubigeo
(
    ubigeo VARCHAR(6) PRIMARY KEY,
    departamento VARCHAR(100) NOT NULL,
    provincia VARCHAR(100) NOT NULL,
    distrito VARCHAR(100) NOT NULL
);
GO

INSERT INTO Ubigeo
VALUES
('130101','LA LIBERTAD','TRUJILLO','TRUJILLO'),
('130102','LA LIBERTAD','TRUJILLO','EL PORVENIR'),
('130103','LA LIBERTAD','TRUJILLO','FLORENCIA DE MORA'),
('130104','LA LIBERTAD','TRUJILLO','HUANCHACO'),
('130105','LA LIBERTAD','TRUJILLO','LA ESPERANZA');
GO

CREATE TABLE Vacunacion
(
    id_vacunacion BIGINT IDENTITY(1,1) PRIMARY KEY,
    departamento VARCHAR(100) NOT NULL,
    provincia VARCHAR(100) NOT NULL,
    distrito VARCHAR(100) NOT NULL,
    fecha_corte DATE NOT NULL,
    dosis_aplicadas INT NOT NULL,
    tipo_vacuna VARCHAR(100) NOT NULL,
    grupo_etario VARCHAR(50) NOT NULL,
    sexo CHAR(1) NOT NULL,
    ubigeo VARCHAR(6) NOT NULL,
    fecha_registro DATETIME2 DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Vacunacion_Ubigeo
        FOREIGN KEY (ubigeo)
        REFERENCES Ubigeo(ubigeo),
    CONSTRAINT CK_Vacunacion_Dosis
        CHECK(dosis_aplicadas > 0),
    CONSTRAINT CK_Vacunacion_Sexo
        CHECK(sexo IN ('M','F'))
);
GO

CREATE TABLE IPRESS
(
    id_ipress INT IDENTITY(1,1) PRIMARY KEY,
    codigo_renipress VARCHAR(20) NOT NULL UNIQUE,
    nombre_ipress VARCHAR(200) NOT NULL,
    departamento VARCHAR(100) NOT NULL,
    provincia VARCHAR(100) NOT NULL,
    distrito VARCHAR(100) NOT NULL,
    tipo_establecimiento VARCHAR(100),
    categoria_ipress VARCHAR(20),
    estado_ipress VARCHAR(20) NOT NULL,
    ubigeo VARCHAR(6) NOT NULL,
    fecha_registro DATETIME2 DEFAULT SYSDATETIME(),
    CONSTRAINT FK_IPRESS_Ubigeo
        FOREIGN KEY (ubigeo)
        REFERENCES Ubigeo(ubigeo),
    CONSTRAINT CK_IPRESS_Estado
        CHECK(estado_ipress IN ('ACTIVO','INACTIVO'))
);
GO

CREATE TABLE Auditoria
(
    id_log BIGINT IDENTITY(1,1) PRIMARY KEY,
    fecha_hora DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    usuario VARCHAR(100) NOT NULL,
    tabla_afectada VARCHAR(100) NOT NULL,
    operacion VARCHAR(20) NOT NULL,
    registros_afectados INT NOT NULL,
    descripcion VARCHAR(500)
);
GO

CREATE TABLE CalidadDatos
(
    id_calidad BIGINT IDENTITY(1,1) PRIMARY KEY,
    id_vacunacion BIGINT NULL,
    tipo_problema VARCHAR(100) NOT NULL,
    columna_afectada VARCHAR(100),
    descripcion VARCHAR(500),
    fecha_deteccion DATETIME2 DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Calidad_Vacunacion
        FOREIGN KEY(id_vacunacion)
        REFERENCES Vacunacion(id_vacunacion)
);
GO


CREATE OR ALTER PROCEDURE usp_CargarVacunacion
(
    @departamento VARCHAR(100),
    @provincia VARCHAR(100),
    @distrito VARCHAR(100),
    @fecha_corte DATE,
    @dosis_aplicadas INT,
    @tipo_vacuna VARCHAR(100),
    @grupo_etario VARCHAR(50),
    @sexo CHAR(1),
    @ubigeo VARCHAR(6)
)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        SAVE TRANSACTION InicioCarga;
        IF NOT EXISTS
        (
            SELECT 1
            FROM Ubigeo
            WHERE ubigeo = @ubigeo
        )
        BEGIN
            THROW 50001,
            'El código UBIGEO ingresado no existe.',
            1;
        END;
        IF @fecha_corte > CAST(GETDATE() AS DATE)
        BEGIN
            THROW 50002,
            'La fecha de corte no puede ser futura.',
            1;
        END;
        IF @dosis_aplicadas <= 0
        BEGIN
            THROW 50003,
            'La cantidad de dosis debe ser mayor a cero.',
            1;
        END;

        IF @sexo NOT IN ('M','F')
        BEGIN

            THROW 50004,
            'El sexo debe ser M o F.',
            1;

        END;

        INSERT INTO Vacunacion
        (
            departamento,
            provincia,
            distrito,
            fecha_corte,
            dosis_aplicadas,
            tipo_vacuna,
            grupo_etario,
            sexo,
            ubigeo
        )
        VALUES
        (
            UPPER(@departamento),
            UPPER(@provincia),
            UPPER(@distrito),
            @fecha_corte,
            @dosis_aplicadas,
            UPPER(@tipo_vacuna),
            @grupo_etario,
            @sexo,
            @ubigeo
        );
        COMMIT TRANSACTION;
        PRINT 'Registro de vacunación ingresado correctamente.';

    END TRY

    BEGIN CATCH

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @MensajeError VARCHAR(4000);
        SET @MensajeError = ERROR_MESSAGE();
        PRINT 'ERROR AL REGISTRAR VACUNACIÓN';
        PRINT @MensajeError;
        THROW;
    END CATCH;
END;
GO



EXEC usp_CargarVacunacion
    @departamento = 'LA LIBERTAD',
    @provincia = 'TRUJILLO',
    @distrito = 'TRUJILLO',
    @fecha_corte = '2026-08-20',
    @dosis_aplicadas = 1,
    @tipo_vacuna = 'PFIZER',
    @grupo_etario = '18-29',
    @sexo = 'M',
    @ubigeo = '130101';
GO

SELECT * FROM Vacunacion;

CREATE OR ALTER PROCEDURE usp_ValidarCalidadVacunacion
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        DELETE FROM CalidadDatos;
        INSERT INTO CalidadDatos
        (
            id_vacunacion,
            tipo_problema,
            columna_afectada,
            descripcion
        )
        SELECT
            id_vacunacion,
            'VALOR NULO',
            'distrito',
            'El distrito se encuentra vacío o nulo'
        FROM Vacunacion
        WHERE distrito IS NULL
        OR LTRIM(RTRIM(distrito)) = '';
        INSERT INTO CalidadDatos
        (
            id_vacunacion,
            tipo_problema,
            columna_afectada,
            descripcion
        )
        SELECT
            id_vacunacion,
            'VALOR NULO',
            'provincia',
            'La provincia se encuentra vacía'
        FROM Vacunacion
        WHERE provincia IS NULL
        OR LTRIM(RTRIM(provincia)) = '';
        INSERT INTO CalidadDatos
        (
            id_vacunacion,
            tipo_problema,
            columna_afectada,
            descripcion
        )
        SELECT
            id_vacunacion,
            'DATO ATIPICO',
            'dosis_aplicadas',
            'La cantidad de dosis debe ser mayor a cero'
        FROM Vacunacion
        WHERE dosis_aplicadas <= 0;
        INSERT INTO CalidadDatos
        (
            id_vacunacion,
            tipo_problema,
            columna_afectada,
            descripcion
        )
        SELECT
            id_vacunacion,
            'FECHA INVALIDA',
            'fecha_corte',
            'La fecha de corte supera la fecha actual'
        FROM Vacunacion
        WHERE fecha_corte > GETDATE();
        COMMIT TRANSACTION;
        SELECT *
        FROM CalidadDatos;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        PRINT 'Error durante la validación de calidad:';
        PRINT ERROR_MESSAGE();
        THROW;
    END CATCH;
END;
GO

EXEC usp_ValidarCalidadVacunacion;

CREATE OR ALTER TRIGGER trg_Auditoria_Vacunacion
ON Vacunacion
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Operacion VARCHAR(20);
    DECLARE @Cantidad INT;
    IF EXISTS(SELECT 1 FROM inserted)
       AND NOT EXISTS(SELECT 1 FROM deleted)
    BEGIN
        SET @Operacion = 'INSERT';
        SELECT @Cantidad = COUNT(*)
        FROM inserted;
    END
    ELSE IF NOT EXISTS(SELECT 1 FROM inserted)
        AND EXISTS(SELECT 1 FROM deleted)
    BEGIN
        SET @Operacion = 'DELETE';
        SELECT @Cantidad = COUNT(*)
        FROM deleted;
    END
    ELSE
    BEGIN
        SET @Operacion = 'UPDATE';
        SELECT @Cantidad = COUNT(*)
        FROM inserted;
    END;


    INSERT INTO Auditoria
    (
        fecha_hora,
        usuario,
        tabla_afectada,
        operacion,
        registros_afectados,
        descripcion
    )
    VALUES
    (
        SYSDATETIME(),
        SYSTEM_USER,
        'Vacunacion',
        @Operacion,
        @Cantidad,
        CONCAT(
            'Operación ',
            @Operacion,
            ' realizada en la tabla Vacunacion'
        )
    );
END;
GO

--INSERT
EXEC usp_CargarVacunacion
    'LA LIBERTAD',
    'TRUJILLO',
    'TRUJILLO',
    '2026-08-20',
    1,
    'PFIZER',
    '18-29',
    'M',
    '130101';

SELECT * FROM Auditoria;

--UPDATE
UPDATE Vacunacion

SET tipo_vacuna = 'MODERNA'

WHERE id_vacunacion = 1;

--DELETE
DELETE FROM Vacunacion
WHERE id_vacunacion = 1;

SELECT *
FROM Auditoria
ORDER BY id_log DESC;


CREATE OR ALTER TRIGGER trg_Integridad_Vacunacion
ON Vacunacion
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS
    (
        SELECT 1
        FROM inserted
        WHERE fecha_corte > CAST(GETDATE() AS DATE)
    )
    BEGIN
        THROW 51001,
        'No se puede registrar una fecha futura.',
        1;
    END;
    IF EXISTS
    (
        SELECT 1
        FROM inserted
        WHERE dosis_aplicadas <= 0
    )
    BEGIN
        THROW 51002,
        'Las dosis aplicadas deben ser mayores a cero.',
        1;
    END;
    IF EXISTS
    (
        SELECT 1
        FROM inserted
        WHERE departamento IS NULL
        OR provincia IS NULL
        OR distrito IS NULL
        OR ubigeo IS NULL
    )
    BEGIN
        THROW 51003,
        'Existen campos obligatorios vacíos.',
        1;
    END;

    INSERT INTO Vacunacion
    (
        departamento,
        provincia,
        distrito,
        fecha_corte,
        dosis_aplicadas,
        tipo_vacuna,
        grupo_etario,
        sexo,
        ubigeo,
        fecha_registro
    )
    SELECT
        departamento,
        provincia,
        distrito,
        fecha_corte,
        dosis_aplicadas,
        tipo_vacuna,
        grupo_etario,
        sexo,
        ubigeo,
        ISNULL(fecha_registro,SYSDATETIME())

    FROM inserted;
END;
GO

INSERT INTO Vacunacion
(
    departamento,
    provincia,
    distrito,
    fecha_corte,
    dosis_aplicadas,
    tipo_vacuna,
    grupo_etario,
    sexo,
    ubigeo
)
VALUES
(
    'LA LIBERTAD',
    'TRUJILLO',
    'TRUJILLO',
    '2035-10-20',
    1,
    'PFIZER',
    '18-29',
    'M',
    '130101'
);

INSERT INTO Vacunacion
(
    departamento,
    provincia,
    distrito,
    fecha_corte,
    dosis_aplicadas,
    tipo_vacuna,
    grupo_etario,
    sexo,
    ubigeo
)

VALUES
(
    'LA LIBERTAD',
    'TRUJILLO',
    'TRUJILLO',
    '2026-08-20',
    -5,
    'PFIZER',
    '18-29',
    'M',
    '130101'
);

CREATE OR ALTER FUNCTION fn_CalcularEdad
(
    @fecha_nacimiento DATE
)
RETURNS INT
AS
BEGIN
    DECLARE @edad INT;
    SET @edad =
        DATEDIFF
        (
            YEAR,
            @fecha_nacimiento,
            GETDATE()
        );
    IF DATEADD
       (
           YEAR,
           @edad,
           @fecha_nacimiento
       ) > CAST(GETDATE() AS DATE)
    BEGIN
        SET @edad = @edad - 1;
    END;
    RETURN @edad;
END;
GO
SELECT dbo.fn_CalcularEdad('2000-05-10')
AS Edad;


USE BD_DIRESA_LALIBERTAD;
GO

CREATE ROLE Administrador;
GO
GRANT CONTROL ON DATABASE::BD_DIRESA_LALIBERTAD TO Administrador;
GO

CREATE ROLE AnalistaDatos;
GO
GRANT SELECT ON Vacunacion TO AnalistaDatos;
GRANT SELECT ON IPRESS TO AnalistaDatos;
GRANT SELECT ON Ubigeo TO AnalistaDatos;
GRANT SELECT ON CalidadDatos TO AnalistaDatos;
GO

CREATE ROLE Auditor;
GO
GRANT SELECT ON Auditoria TO Auditor;
GRANT SELECT ON CalidadDatos TO Auditor;
GO

-- Usuario Administrador
CREATE LOGIN usr_admin WITH PASSWORD = 'Admin123!';
CREATE USER usr_admin FOR LOGIN usr_admin;
EXEC sp_addrolemember 'Administrador', 'usr_admin';
GO

-- Usuario Analista
CREATE LOGIN usr_analista WITH PASSWORD = 'Analista123!';
CREATE USER usr_analista FOR LOGIN usr_analista;
EXEC sp_addrolemember 'AnalistaDatos', 'usr_analista';
GO

-- Usuario Auditor
CREATE LOGIN usr_auditor WITH PASSWORD = 'Auditor123!';
CREATE USER usr_auditor FOR LOGIN usr_auditor;
EXEC sp_addrolemember 'Auditor', 'usr_auditor';
GO

-- VERIFICAR PERMISOS
EXEC sp_helprolemember 'Administrador';
EXEC sp_helprolemember 'AnalistaDatos';
EXEC sp_helprolemember 'Auditor';
GO

-- Ver permisos del usuario analista
EXEC sp_helprotect NULL, 'AnalistaDatos';
GO

-- CONFIGURAR MODELO DE RECUPERACIÓN
ALTER DATABASE BD_DIRESA_LALIBERTAD SET RECOVERY FULL;
GO

-- RESPALDO COMPLETO -- Ejecutar semanalmente
BACKUP DATABASE BD_DIRESA_LALIBERTAD
TO DISK = 'C:\Backups\BD_DIRESA_LALIBERTAD_FULL.bak'
WITH FORMAT,
     NAME = 'Backup Completo BD_DIRESA_LALIBERTAD',
     DESCRIPTION = 'Backup FULL - Semanal',
     STATS = 10;
GO

-- RESPALDO DIFERENCIAL -- Ejecutar diariamente
BACKUP DATABASE BD_DIRESA_LALIBERTAD
TO DISK = 'C:\Backups\BD_DIRESA_LALIBERTAD_DIFF.bak'
WITH DIFFERENTIAL,
     NAME = 'Backup Diferencial BD_DIRESA_LALIBERTAD',
     DESCRIPTION = 'Backup DIFFERENTIAL - Diario',
     STATS = 10;
GO

-- RESPALDO DE LOG -- Ejecutar cada 15-30 minutos
BACKUP DATABASE BD_DIRESA_LALIBERTAD
TO DISK = 'C:\Backups\BD_DIRESA_LALIBERTAD_LOG.trn'
WITH NAME = 'Backup log BD_DIRESA_LALIBERTAD',
     DESCRIPTION = 'Backup LOG - Cada 15 minutos',
     STATS = 10;
GO

-- RESTAURACIÓN COMPLETA (FULL)
USE master;
GO

RESTORE DATABASE BD_DIRESA_LALIBERTAD
FROM DISK = 'C:\Backups\BD_DIRESA_LALIBERTAD_FULL.bak'
WITH REPLACE,
     STATS = 10;
GO

-- Verificar que la base de datos está operativa
USE BD_DIRESA_LALIBERTAD;
GO

SELECT name, state_desc FROM sys.databases WHERE name = 'BD_DIRESA_LALIBERTAD';
GO


-- ============================================================
-- CONSULTA CRÍTICA (SIN ÍNDICE)
-- ============================================================
USE BD_DIRESA_LALIBERTAD;
GO
SET STATISTICS TIME ON;
SET STATISTICS IO ON;
GO
SELECT 
    provincia,
    COUNT(*) AS total_registros,
    SUM(dosis_aplicadas) AS total_dosis_aplicadas,
    AVG(dosis_aplicadas) AS promedio_dosis
FROM Vacunacion
WHERE departamento = 'LA LIBERTAD'
  AND fecha_corte BETWEEN '2025-01-01' AND '2026-12-31'
GROUP BY provincia
ORDER BY provincia;
GO
SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO

-- ============================================================
-- CREACIÓN DE ÍNDICE PARA MEJORAR RENDIMIENTO
-- ============================================================
CREATE NONCLUSTERED INDEX IX_Vacunacion_Departamento_Fecha
ON Vacunacion (departamento, fecha_corte)
INCLUDE (provincia, distrito, dosis_aplicadas);
GO

-- ============================================================
-- CONSULTA CRÍTICA (CON ÍNDICE)
-- ============================================================
SET STATISTICS TIME ON;
SET STATISTICS IO ON;
GO

SELECT 
    provincia,
    COUNT(*) AS total_registros,
    SUM(dosis_aplicadas) AS total_dosis_aplicadas,
    AVG(dosis_aplicadas) AS promedio_dosis
FROM Vacunacion WITH (INDEX(IX_Vacunacion_Departamento_Fecha))
WHERE departamento = 'LA LIBERTAD'
  AND fecha_corte BETWEEN '2025-01-01' AND '2026-12-31'
GROUP BY provincia
ORDER BY provincia;
GO

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO



/* Seccion 7 */

USE BD_DIRESA_LALIBERTAD;   -- o la base que prefieras
GO

/* ---------- PASO 1: crear la tabla ---------- */
DROP TABLE IF EXISTS dbo.vacunas_covid;
GO
CREATE TABLE dbo.vacunas_covid
(
    FECHA_CORTE          VARCHAR(8),
    UUID                 BIGINT,
    GRUPO_RIESGO         VARCHAR(200),
    EDAD                 INT,
    SEXO                 VARCHAR(20),
    FECHA_VACUNACION     VARCHAR(8),
    DOSIS                INT,
    FABRICANTE           VARCHAR(50),
    DIRESA               VARCHAR(100),
    DEPARTAMENTO         VARCHAR(100),
    PROVINCIA            VARCHAR(100),
    DISTRITO             VARCHAR(100),
    TIPO_EDAD            VARCHAR(5),
    CLASIFICACION_VACUNA VARCHAR(10)
);
GO

/* ---------- PASO 2: importar el CSV ----------*/
BULK INSERT dbo.vacunas_covid
FROM 'C:\Users\akevy\Downloads\vacunas_covid.csv'
WITH (
    FORMAT = 'CSV',
    FIELDQUOTE = '"',
    FIRSTROW = 2,
    CODEPAGE = '65001',      -- UTF-8 (para Ñ y tildes)
    KEEPNULLS,               -- campos vacíos quedan como NULL
    TABLOCK
);
GO

/* ---------- PASO 3: verificar la carga ---------- */
SELECT COUNT(*) AS filas,
       SUM(CASE WHEN FABRICANTE IS NULL THEN 1 ELSE 0 END) AS fabricante_nulo
FROM dbo.vacunas_covid;
GO


SET STATISTICS TIME ON;

-- A
SELECT COUNT(*), SUM(DOSIS), AVG(CAST(DOSIS AS FLOAT)), MIN(DOSIS), MAX(DOSIS)
FROM dbo.vacunas_covid;

-- B
SELECT ISNULL(FABRICANTE,'SIN FABRICANTE') AS FABRICANTE, COUNT(*) AS n, SUM(DOSIS) AS s
FROM dbo.vacunas_covid
GROUP BY ISNULL(FABRICANTE,'SIN FABRICANTE');

-- C
SELECT PROVINCIA, COUNT(*) AS n, SUM(DOSIS) AS s, AVG(CAST(DOSIS AS FLOAT)) AS a
FROM dbo.vacunas_covid
WHERE DEPARTAMENTO = 'LA LIBERTAD'
GROUP BY PROVINCIA
ORDER BY PROVINCIA;

SET STATISTICS TIME OFF;
GO


SET NOCOUNT ON;
DROP TABLE IF EXISTS #tiempos;
CREATE TABLE #tiempos (op CHAR(1), corrida INT, ms DECIMAL(12,2));

DECLARE @op CHAR(1), @i INT, @t0 DATETIME2(7), @t1 DATETIME2(7);

DECLARE @ops TABLE (op CHAR(1));
INSERT INTO @ops VALUES ('A'),('B'),('C');

DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT op FROM @ops ORDER BY op;
OPEN c; FETCH NEXT FROM c INTO @op;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @i = 0;                       -- corrida 0 = calentamiento (no cuenta)
    WHILE @i <= 5
    BEGIN
        DROP TABLE IF EXISTS #rA; DROP TABLE IF EXISTS #rB; DROP TABLE IF EXISTS #rC;
        SET @t0 = SYSDATETIME();

        IF @op = 'A'
            SELECT COUNT(*) AS n, SUM(DOSIS) AS s, AVG(CAST(DOSIS AS FLOAT)) AS a,
                   MIN(DOSIS) AS mn, MAX(DOSIS) AS mx
            INTO #rA FROM dbo.vacunas_covid;
        ELSE IF @op = 'B'
            SELECT ISNULL(FABRICANTE,'SIN FABRICANTE') AS f, COUNT(*) AS n, SUM(DOSIS) AS s
            INTO #rB FROM dbo.vacunas_covid
            GROUP BY ISNULL(FABRICANTE,'SIN FABRICANTE');
        ELSE
            SELECT PROVINCIA, COUNT(*) AS n, SUM(DOSIS) AS s, AVG(CAST(DOSIS AS FLOAT)) AS a
            INTO #rC FROM dbo.vacunas_covid
            WHERE DEPARTAMENTO = 'LA LIBERTAD'
            GROUP BY PROVINCIA;

        SET @t1 = SYSDATETIME();
        IF @i > 0
            INSERT INTO #tiempos
            VALUES (@op, @i, DATEDIFF_BIG(MICROSECOND, @t0, @t1) / 1000.0);
        SET @i += 1;
    END
    FETCH NEXT FROM c INTO @op;
END
CLOSE c; DEALLOCATE c;

SELECT op AS operacion,
       CAST(AVG(ms) AS DECIMAL(12,1)) AS media_ms,
       CAST(MIN(ms) AS DECIMAL(12,1)) AS min_ms
FROM #tiempos
GROUP BY op
ORDER BY op;
