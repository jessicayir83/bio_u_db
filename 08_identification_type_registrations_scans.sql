/*
==================================================================
 Bio U - Tipo de identificacion, historial de registros y escaneos
==================================================================
 Ejecutar contra BiometricPlatformDB DESPUES del script
 07_create_blocked_ip_table.sql.

 Este script es idempotente: puede ejecutarse varias veces sin
 error (cada paso verifica si ya se aplico). Cada paso va en su
 propio lote (GO) porque SQL Server no deja usar una columna nueva
 en el mismo lote en que se crea.

 Cambios:
 1. [identity].BiometricPerson.IdentificationType: CEDULA | DIMEX |
    PASAPORTE | OTRO. Las filas existentes quedan como CEDULA.
    NationalId pasa a ser "numero de identificacion" (de cualquier
    tipo); se guarda normalizado (sin guiones ni espacios).
 2. Unicidad: ya no por NationalId solo, sino por (tipo + numero).
 3. [identity].BiometricPerson.LastCheckInAt: fecha/hora del ultimo
    ingreso concedido en el kiosco (columna "Ultimo escaneo" del
    listado). Se completa con el historial de biometric.AccessLog.
 4. biometric.AccessLog pasa a ser el historial de escaneos de rostro
    con estado: Status (GRANTED, DENIED, AMBIGUOUS, MATCH, NO_MATCH,
    REJECTED) y Channel (KIOSK_CHECKIN, PANEL_VERIFICATION).
 5. [identity].PersonRegistration: cada intento de registro de una
    persona (kiosco o panel) con su resultado y el tipo/numero de
    identificacion usado, para detectar duplicados e intentos de
    registrarse dos veces o con la identificacion de otra persona.

 Nota: PersonRegistration guarda el numero de identificacion (dato
 personal) tambien en intentos fallidos: es lo que permite ver que
 alguien intento registrarse con la cedula de otra persona. Nunca
 guarda nombres, fotos ni datos biometricos.
==================================================================
*/

USE BiometricPlatformDB;
GO

-- 1. Tipo de identificacion -----------------------------------------------
IF COL_LENGTH('identity.BiometricPerson', 'IdentificationType') IS NULL
    ALTER TABLE [identity].BiometricPerson
        ADD IdentificationType NVARCHAR(20) NOT NULL
            CONSTRAINT DF_BiometricPerson_IdentificationType DEFAULT (N'CEDULA') WITH VALUES;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_BiometricPerson_IdentificationType')
    ALTER TABLE [identity].BiometricPerson
        ADD CONSTRAINT CK_BiometricPerson_IdentificationType
            CHECK (IdentificationType IN (N'CEDULA', N'DIMEX', N'PASAPORTE', N'OTRO'));
GO

-- Normaliza cedulas existentes (quita guiones/espacios) si no chocan con otra fila.
UPDATE p
SET NationalId = REPLACE(REPLACE(p.NationalId, N'-', N''), N' ', N'')
FROM [identity].BiometricPerson p
WHERE p.IdentificationType = N'CEDULA'
  AND (p.NationalId LIKE N'%-%' OR p.NationalId LIKE N'% %')
  AND NOT EXISTS (
      SELECT 1 FROM [identity].BiometricPerson other
      WHERE other.Id <> p.Id
        AND other.IdentificationType = p.IdentificationType
        AND other.NationalId = REPLACE(REPLACE(p.NationalId, N'-', N''), N' ', N'')
  );
GO

-- 2. Unicidad por tipo + numero ---------------------------------------------
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_BiometricPerson_NationalId')
    ALTER TABLE [identity].BiometricPerson DROP CONSTRAINT UQ_BiometricPerson_NationalId;
GO

IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_BiometricPerson_Identification')
    ALTER TABLE [identity].BiometricPerson
        ADD CONSTRAINT UQ_BiometricPerson_Identification UNIQUE (IdentificationType, NationalId);
GO

-- 3. Ultimo ingreso -----------------------------------------------------------
IF COL_LENGTH('identity.BiometricPerson', 'LastCheckInAt') IS NULL
    ALTER TABLE [identity].BiometricPerson ADD LastCheckInAt DATETIME2 NULL;
GO

UPDATE p
SET LastCheckInAt = last_access.OccurredAt
FROM [identity].BiometricPerson p
CROSS APPLY (
    SELECT MAX(a.OccurredAt) AS OccurredAt
    FROM biometric.AccessLog a
    WHERE a.PersonId = p.Id AND a.Granted = 1
) last_access
WHERE p.LastCheckInAt IS NULL AND last_access.OccurredAt IS NOT NULL;
GO

-- 4. Historial de escaneos con estado ----------------------------------------
IF COL_LENGTH('biometric.AccessLog', 'Status') IS NULL
    ALTER TABLE biometric.AccessLog ADD Status NVARCHAR(20) NULL;
GO

IF COL_LENGTH('biometric.AccessLog', 'Channel') IS NULL
    ALTER TABLE biometric.AccessLog
        ADD Channel NVARCHAR(20) NOT NULL
            CONSTRAINT DF_AccessLog_Channel DEFAULT (N'KIOSK_CHECKIN') WITH VALUES;
GO

UPDATE biometric.AccessLog
SET Status = CASE WHEN Granted = 1 THEN N'GRANTED' ELSE N'DENIED' END
WHERE Status IS NULL;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('biometric.AccessLog') AND name = 'Status' AND is_nullable = 1
)
    ALTER TABLE biometric.AccessLog ALTER COLUMN Status NVARCHAR(20) NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_AccessLog_Status')
    ALTER TABLE biometric.AccessLog
        ADD CONSTRAINT CK_AccessLog_Status
            CHECK (Status IN (N'GRANTED', N'DENIED', N'AMBIGUOUS', N'MATCH', N'NO_MATCH', N'REJECTED'));
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_AccessLog_Channel')
    ALTER TABLE biometric.AccessLog
        ADD CONSTRAINT CK_AccessLog_Channel CHECK (Channel IN (N'KIOSK_CHECKIN', N'PANEL_VERIFICATION'));
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AccessLog_PersonId_OccurredAt' AND object_id = OBJECT_ID('biometric.AccessLog'))
    CREATE INDEX IX_AccessLog_PersonId_OccurredAt ON biometric.AccessLog(PersonId, OccurredAt DESC);
GO

-- 5. Historial de registros -----------------------------------------------------
IF OBJECT_ID(N'identity.PersonRegistration', N'U') IS NULL
BEGIN
    CREATE TABLE [identity].PersonRegistration (
        Id                    INT IDENTITY(1,1) NOT NULL,
        OccurredAt            DATETIME2(3)       NOT NULL CONSTRAINT DF_PersonRegistration_OccurredAt DEFAULT (SYSUTCDATETIME()),
        Channel               NVARCHAR(20)       NOT NULL,   -- KIOSK | PANEL
        Status                NVARCHAR(30)       NOT NULL,   -- ver CK_PersonRegistration_Status
        IdentificationType    NVARCHAR(20)       NOT NULL,
        IdentificationNumber  NVARCHAR(50)       NOT NULL,   -- normalizado
        PersonId              INT                NULL,       -- persona creada (SUCCESS) o ya existente con la que choco
        SourceIp              NVARCHAR(64)       NULL,
        CreatedByUserId       INT                NULL,       -- usuario del panel (NULL en el kiosco)
        Detail                NVARCHAR(400)      NULL,       -- motivo legible del rechazo
        CONSTRAINT PK_PersonRegistration PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT CK_PersonRegistration_Channel CHECK (Channel IN (N'KIOSK', N'PANEL')),
        CONSTRAINT CK_PersonRegistration_Status CHECK (Status IN (
            N'SUCCESS',            -- persona registrada
            N'DUPLICATE_ID',       -- el tipo + numero ya pertenece a una persona
            N'DUPLICATE_FACE',     -- el rostro ya estaba registrado con esa misma identificacion
            N'IDENTITY_MISMATCH',  -- el rostro ya estaba registrado con OTRA identificacion
            N'REJECTED_PHOTOS'     -- las fotos no pasaron el control de calidad
        )),
        CONSTRAINT CK_PersonRegistration_IdentificationType CHECK (IdentificationType IN (N'CEDULA', N'DIMEX', N'PASAPORTE', N'OTRO'))
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_PersonRegistration_Identification' AND object_id = OBJECT_ID('identity.PersonRegistration'))
    CREATE INDEX IX_PersonRegistration_Identification
        ON [identity].PersonRegistration(IdentificationType, IdentificationNumber, OccurredAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_PersonRegistration_PersonId' AND object_id = OBJECT_ID('identity.PersonRegistration'))
    CREATE INDEX IX_PersonRegistration_PersonId ON [identity].PersonRegistration(PersonId, OccurredAt DESC);
GO

PRINT 'Tipo de identificacion, historial de registros (identity.PersonRegistration) y escaneos con estado (biometric.AccessLog) listos.';
GO
