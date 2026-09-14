/*
==================================================================
 Biometric Platform - Modulo Kiosco
 Script: Bitacora de ingresos (schema `biometric`)
==================================================================
 Ejecutar contra BiometricPlatformDB DESPUES del script
 04_create_biometric_template_table.sql.

 Este script es idempotente: puede ejecutarse varias veces sin
 error si la tabla ya existe.

 IMPORTANTE: esta tabla NUNCA guarda la foto ni el descriptor
 biometrico - solo el resultado del evento (quien, cuando, si se
 concedio el acceso). Mismo principio que el schema `audit`.

 PersonId es NULL cuando la identificacion 1:N no reconocio a
 nadie (intento denegado).
==================================================================
*/

USE BiometricPlatformDB;
GO

IF OBJECT_ID(N'biometric.AccessLog', N'U') IS NULL
BEGIN
    CREATE TABLE biometric.AccessLog (
        Id          INT IDENTITY(1,1) NOT NULL,
        PersonId    INT                NULL,       -- NULL = no se identifico a nadie
        Modality    NVARCHAR(30)       NOT NULL,   -- 'Face', 'Fingerprint', etc.
        Granted     BIT                NOT NULL,
        Distance    FLOAT              NULL,       -- distancia del mejor match (informativa)
        SourceIp    NVARCHAR(64)       NULL,
        OccurredAt  DATETIME2          NOT NULL CONSTRAINT DF_AccessLog_OccurredAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_AccessLog PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_AccessLog_Person FOREIGN KEY (PersonId) REFERENCES [identity].BiometricPerson(Id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AccessLog_PersonId' AND object_id = OBJECT_ID('biometric.AccessLog'))
    CREATE INDEX IX_AccessLog_PersonId ON biometric.AccessLog(PersonId);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AccessLog_OccurredAt' AND object_id = OBJECT_ID('biometric.AccessLog'))
    CREATE INDEX IX_AccessLog_OccurredAt ON biometric.AccessLog(OccurredAt DESC);
GO

-- Usuario de sistema del kiosco --------------------------------------
-- identity.BiometricPerson.CreatedByUserId es NOT NULL (trazabilidad de
-- quien registro a cada persona), pero en el kiosco publico no hay nadie
-- logueado. Este usuario de sistema queda como autor de esos registros.
--
-- NO puede iniciar sesion: IsActive = 0 (AuthService rechaza usuarios
-- inactivos) y el PasswordHash no es un hash bcrypt valido, asi que
-- ninguna contrasena puede coincidir. Tampoco se le asigna ningun rol.
IF NOT EXISTS (SELECT 1 FROM security.[User] WHERE Username = 'kiosk')
BEGIN
    INSERT INTO security.[User] (Username, Email, PasswordHash, FullName, IsActive)
    VALUES ('kiosk', 'kiosk@biometric.local', 'NOLOGIN-SYSTEM-ACCOUNT', 'Kiosco (usuario de sistema)', 0);
END
GO

PRINT 'Modulo Kiosco: tabla biometric.AccessLog y usuario de sistema kiosk creados.';
GO
