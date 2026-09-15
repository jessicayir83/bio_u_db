/*
==================================================================
 Bio U - Fase 5: Reconocimiento facial (parcial)
 Script: Tabla de templates biométricos (schema `biometric`)
==================================================================
 Ejecutar contra BiometricPlatformDB DESPUES del script
 03_create_identity_biometric_tables.sql.

 Este script es idempotente: puede ejecutarse varias veces sin
 error si la tabla ya existe.

 IMPORTANTE: el vector se guarda SIN CIFRAR (Fase 7 se encarga del
 cifrado de templates a nivel de aplicación). Solo Face en esta fase.
==================================================================
*/

USE BiometricPlatformDB;
GO

IF OBJECT_ID(N'biometric.Template', N'U') IS NULL
BEGIN
    CREATE TABLE biometric.Template (
        Id            INT IDENTITY(1,1) NOT NULL,
        PersonId      INT                NOT NULL,
        EnrollmentId  INT                NOT NULL,
        Modality      NVARCHAR(30)       NOT NULL CONSTRAINT DF_Template_Modality DEFAULT ('Face'),
        Vector        NVARCHAR(MAX)      NOT NULL,  -- JSON del arreglo de floats del descriptor. SIN CIFRAR (Fase 7).
        CreatedAt     DATETIME2          NOT NULL CONSTRAINT DF_Template_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_Template PRIMARY KEY CLUSTERED (Id),
        -- ON DELETE NO ACTION en PersonId (no CASCADE): SQL Server no permite
        -- dos rutas de cascada hacia la misma tabla (Person->Template directo
        -- y Person->Enrollment->Template). La cascada real ocurre vía
        -- Enrollment: al borrar un Enrollment se borra su Template.
        CONSTRAINT FK_Template_Person FOREIGN KEY (PersonId) REFERENCES [identity].BiometricPerson(Id),
        CONSTRAINT FK_Template_Enrollment FOREIGN KEY (EnrollmentId) REFERENCES biometric.Enrollment(Id) ON DELETE CASCADE
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Template_PersonId' AND object_id = OBJECT_ID('biometric.Template'))
    CREATE INDEX IX_Template_PersonId ON biometric.Template(PersonId);
GO

PRINT 'Fase 5 (parcial) completa: tabla biometric.Template creada.';
GO
