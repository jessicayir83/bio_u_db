/*
==================================================================
 Bio U - Fase 3: Gestion de Personas
 Script: Tablas de identidad (schema `identity`) y enrollment
         (schema `biometric`, solo estructura/estado)
==================================================================
 Ejecutar contra BiometricPlatformDB DESPUES del script
 02_create_security_tables.sql.

 Este script es idempotente: puede ejecutarse varias veces sin
 error si las tablas ya existen.

 IMPORTANTE: TypeORM tiene synchronize=false. Este script es la
 UNICA fuente de verdad para crear/alterar estas tablas.

 Nota: biometric.Template (contenido biometrico real) NO se crea
 aqui - se activa en Fase 5 cuando exista captura real.

 Nota tecnica: `identity` es palabra reservada en T-SQL (igual que
 `USER`), asi que toda referencia al schema va entre corchetes:
 [identity].NombreTabla.
==================================================================
*/

USE BiometricPlatformDB;
GO

-- 1) [identity].BiometricPerson -------------------------------------------
IF OBJECT_ID(N'identity.BiometricPerson', N'U') IS NULL
BEGIN
    CREATE TABLE [identity].BiometricPerson (
        Id               INT IDENTITY(1,1) NOT NULL,
        NationalId       NVARCHAR(50)       NOT NULL,  -- cedula, identificador primario de la persona
        FirstName        NVARCHAR(150)      NOT NULL,
        LastName         NVARCHAR(150)      NOT NULL,
        DateOfBirth      DATE               NULL,
        IsActive         BIT                NOT NULL CONSTRAINT DF_BiometricPerson_IsActive DEFAULT (1),
        CreatedByUserId  INT                NOT NULL,  -- referencia a security.User(Id); sin FK de TypeORM a proposito (ver CLAUDE.md)
        CreatedAt        DATETIME2          NOT NULL CONSTRAINT DF_BiometricPerson_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt        DATETIME2          NULL,
        CONSTRAINT PK_BiometricPerson PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_BiometricPerson_NationalId UNIQUE (NationalId),
        CONSTRAINT FK_BiometricPerson_CreatedByUser FOREIGN KEY (CreatedByUserId) REFERENCES security.[User](Id)
    );
END
GO

-- 2) [identity].PersonIdentifier (identificadores secundarios) ------------
IF OBJECT_ID(N'identity.PersonIdentifier', N'U') IS NULL
BEGIN
    CREATE TABLE [identity].PersonIdentifier (
        Id               INT IDENTITY(1,1) NOT NULL,
        PersonId         INT                NOT NULL,
        IdentifierType   NVARCHAR(50)       NOT NULL,  -- texto libre: 'EmployeeCode', 'Passport', etc. (la cedula vive en BiometricPerson.NationalId)
        IdentifierValue  NVARCHAR(150)      NOT NULL,
        CreatedAt        DATETIME2          NOT NULL CONSTRAINT DF_PersonIdentifier_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_PersonIdentifier PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_PersonIdentifier_TypeValue UNIQUE (IdentifierType, IdentifierValue),
        CONSTRAINT FK_PersonIdentifier_Person FOREIGN KEY (PersonId) REFERENCES [identity].BiometricPerson(Id) ON DELETE CASCADE
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_PersonIdentifier_PersonId' AND object_id = OBJECT_ID('identity.PersonIdentifier'))
    CREATE INDEX IX_PersonIdentifier_PersonId ON [identity].PersonIdentifier(PersonId);
GO

-- 3) biometric.Enrollment (solo estructura/estado, sin datos biometricos) -
IF OBJECT_ID(N'biometric.Enrollment', N'U') IS NULL
BEGIN
    CREATE TABLE biometric.Enrollment (
        Id               INT IDENTITY(1,1) NOT NULL,
        PersonId         INT                NOT NULL,
        Modality         NVARCHAR(30)       NOT NULL,  -- texto libre: 'Face', 'Fingerprint', etc.
        Status           NVARCHAR(20)       NOT NULL CONSTRAINT DF_Enrollment_Status DEFAULT ('Pending'),  -- Pending | Completed | Revoked
        CreatedByUserId  INT                NOT NULL,  -- referencia a security.User(Id); sin FK de TypeORM a proposito
        CreatedAt        DATETIME2          NOT NULL CONSTRAINT DF_Enrollment_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt        DATETIME2          NULL,
        CompletedAt      DATETIME2          NULL,
        CONSTRAINT PK_Enrollment PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_Enrollment_Person FOREIGN KEY (PersonId) REFERENCES [identity].BiometricPerson(Id) ON DELETE CASCADE,
        CONSTRAINT FK_Enrollment_CreatedByUser FOREIGN KEY (CreatedByUserId) REFERENCES security.[User](Id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Enrollment_PersonId' AND object_id = OBJECT_ID('biometric.Enrollment'))
    CREATE INDEX IX_Enrollment_PersonId ON biometric.Enrollment(PersonId);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Enrollment_Status' AND object_id = OBJECT_ID('biometric.Enrollment'))
    CREATE INDEX IX_Enrollment_Status ON biometric.Enrollment(Status);
GO

PRINT 'Fase 3 completa: tablas de identity.BiometricPerson, identity.PersonIdentifier y biometric.Enrollment creadas.';
GO
