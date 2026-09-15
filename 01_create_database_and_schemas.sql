/*
==================================================================
 Bio U - Fase 1: Foundation Local
 Script: Creación de base de datos y schemas
==================================================================
 Ejecutar este script contra tu instancia local de SQL Server
 (SQL Server Management Studio, Azure Data Studio, o sqlcmd).

 Este script es idempotente: puede ejecutarse varias veces sin
 error si la base o los schemas ya existen.
==================================================================
*/

-- 1) Crear la base de datos
IF DB_ID(N'BiometricPlatformDB') IS NULL
BEGIN
    CREATE DATABASE BiometricPlatformDB;
END
GO

USE BiometricPlatformDB;
GO

-- 2) Crear los schemas lógicos
--    identity  -> personas biométricas y sus identificadores externos
--    biometric -> enrollments y templates (cifrados)
--    security  -> usuarios, roles, aplicaciones cliente, tokens
--    audit     -> bitácora de eventos (nunca contenido biométrico)

-- `identity` es palabra reservada en T-SQL (por la propiedad IDENTITY de
-- las columnas) -> el nombre de schema va entre corchetes al crearlo.
IF SCHEMA_ID(N'identity') IS NULL
    EXEC('CREATE SCHEMA [identity] AUTHORIZATION dbo');
GO

IF SCHEMA_ID(N'biometric') IS NULL
    EXEC('CREATE SCHEMA biometric AUTHORIZATION dbo');
GO

IF SCHEMA_ID(N'security') IS NULL
    EXEC('CREATE SCHEMA security AUTHORIZATION dbo');
GO

IF SCHEMA_ID(N'audit') IS NULL
    EXEC('CREATE SCHEMA audit AUTHORIZATION dbo');
GO

-- 3) Verificación rápida
SELECT name AS schema_name
FROM sys.schemas
WHERE name IN ('identity', 'biometric', 'security', 'audit')
ORDER BY name;
GO

PRINT 'Fase 1 completa: BiometricPlatformDB y schemas creados.';
GO

/*
==================================================================
 Siguiente paso (Fase 2/3 - NO ejecutar todavía):
 Se te entregará un script separado con las tablas de negocio
 (identity.BiometricPerson, identity.PersonIdentifier,
  biometric.Enrollment, biometric.Template,
  security.User / Role / ClientApplication / RefreshToken,
  audit.AuditLog) cuando avancemos a esa etapa, para no adelantar
 estructura que el API todavía no va a usar.
==================================================================
*/
