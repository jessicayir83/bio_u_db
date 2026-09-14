/*
==================================================================
 Biometric Platform - Fase 2: Identity y Security
 Script: Tablas de seguridad (schema `security`)
==================================================================
 Ejecutar contra BiometricPlatformDB DESPUES del script
 01_create_database_and_schemas.sql.

 Este script es idempotente: puede ejecutarse varias veces sin
 error si las tablas ya existen.

 IMPORTANTE: TypeORM tiene synchronize=false (ver database.module.ts).
 Este script es la UNICA fuente de verdad para crear/alterar estas
 tablas. Cualquier cambio futuro de estructura llega en un script
 nuevo numerado (03_..., 04_...), nunca modificando este archivo
 despues de haberlo ejecutado en produccion/local.
==================================================================
*/

USE BiometricPlatformDB;
GO

-- 1) security.Role -----------------------------------------------------
IF OBJECT_ID(N'security.Role', N'U') IS NULL
BEGIN
    CREATE TABLE security.Role (
        Id           INT IDENTITY(1,1) NOT NULL,
        Name         NVARCHAR(50)      NOT NULL,
        Description  NVARCHAR(200)     NULL,
        CreatedAt    DATETIME2         NOT NULL CONSTRAINT DF_Role_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_Role PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_Role_Name UNIQUE (Name)
    );
END
GO

-- 2) security.[User] (USER es palabra reservada en T-SQL) --------------
IF OBJECT_ID(N'security.User', N'U') IS NULL
BEGIN
    CREATE TABLE security.[User] (
        Id            INT IDENTITY(1,1) NOT NULL,
        Username      NVARCHAR(100)     NOT NULL,
        Email         NVARCHAR(256)     NOT NULL,
        PasswordHash  NVARCHAR(200)     NOT NULL,
        FullName      NVARCHAR(200)     NULL,
        IsActive      BIT               NOT NULL CONSTRAINT DF_User_IsActive DEFAULT (1),
        CreatedAt     DATETIME2         NOT NULL CONSTRAINT DF_User_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt     DATETIME2         NULL,
        LastLoginAt   DATETIME2         NULL,
        CONSTRAINT PK_User PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_User_Username UNIQUE (Username),
        CONSTRAINT UQ_User_Email UNIQUE (Email)
    );
END
GO

-- 3) security.UserRole (puente many-to-many) ----------------------------
IF OBJECT_ID(N'security.UserRole', N'U') IS NULL
BEGIN
    CREATE TABLE security.UserRole (
        UserId      INT       NOT NULL,
        RoleId      INT       NOT NULL,
        AssignedAt  DATETIME2 NOT NULL CONSTRAINT DF_UserRole_AssignedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_UserRole PRIMARY KEY CLUSTERED (UserId, RoleId),
        CONSTRAINT FK_UserRole_User FOREIGN KEY (UserId) REFERENCES security.[User](Id) ON DELETE CASCADE,
        CONSTRAINT FK_UserRole_Role FOREIGN KEY (RoleId) REFERENCES security.Role(Id) ON DELETE CASCADE
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_UserRole_RoleId' AND object_id = OBJECT_ID('security.UserRole'))
    CREATE INDEX IX_UserRole_RoleId ON security.UserRole(RoleId);
GO

-- 4) security.ClientApplication (solo estructura, Fase 8 la activa) -----
IF OBJECT_ID(N'security.ClientApplication', N'U') IS NULL
BEGIN
    CREATE TABLE security.ClientApplication (
        Id                INT IDENTITY(1,1) NOT NULL,
        ClientId          NVARCHAR(100)      NOT NULL,
        ClientSecretHash  NVARCHAR(200)      NOT NULL,
        Name              NVARCHAR(200)      NOT NULL,
        IsActive          BIT                NOT NULL CONSTRAINT DF_ClientApplication_IsActive DEFAULT (1),
        CreatedAt         DATETIME2          NOT NULL CONSTRAINT DF_ClientApplication_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_ClientApplication PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_ClientApplication_ClientId UNIQUE (ClientId)
    );
END
GO

-- 5) security.RefreshToken ----------------------------------------------
IF OBJECT_ID(N'security.RefreshToken', N'U') IS NULL
BEGIN
    CREATE TABLE security.RefreshToken (
        Id                   INT IDENTITY(1,1) NOT NULL,
        UserId               INT                NOT NULL,
        TokenHash            NVARCHAR(128)      NOT NULL,  -- SHA-256 hex (64 chars) del refresh token plano, nunca el token en si
        ExpiresAt            DATETIME2          NOT NULL,
        CreatedAt            DATETIME2          NOT NULL CONSTRAINT DF_RefreshToken_CreatedAt DEFAULT (SYSUTCDATETIME()),
        RevokedAt            DATETIME2          NULL,
        ReplacedByTokenHash  NVARCHAR(128)      NULL,       -- traza la cadena de rotacion
        CreatedByIp          NVARCHAR(64)       NULL,
        CONSTRAINT PK_RefreshToken PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_RefreshToken_User FOREIGN KEY (UserId) REFERENCES security.[User](Id) ON DELETE CASCADE
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_RefreshToken_TokenHash' AND object_id = OBJECT_ID('security.RefreshToken'))
    CREATE INDEX IX_RefreshToken_TokenHash ON security.RefreshToken(TokenHash);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_RefreshToken_UserId' AND object_id = OBJECT_ID('security.RefreshToken'))
    CREATE INDEX IX_RefreshToken_UserId ON security.RefreshToken(UserId);
GO

-- 6) Seed: roles iniciales -----------------------------------------------
IF NOT EXISTS (SELECT 1 FROM security.Role WHERE Name = 'Admin')
    INSERT INTO security.Role (Name, Description) VALUES ('Admin', 'Acceso total a la plataforma');
IF NOT EXISTS (SELECT 1 FROM security.Role WHERE Name = 'Operator')
    INSERT INTO security.Role (Name, Description) VALUES ('Operator', 'Operacion diaria: enrollment y verificacion');
IF NOT EXISTS (SELECT 1 FROM security.Role WHERE Name = 'Auditor')
    INSERT INTO security.Role (Name, Description) VALUES ('Auditor', 'Solo lectura, acceso a bitacoras de auditoria');
GO

-- 7) Seed: usuario Admin inicial ------------------------------------------
-- Password temporal (NO queda en este repo, se te entrega aparte):
-- cambiala apenas puedas iniciar sesion. El hash de abajo se genero con
-- bcryptjs, 10 salt rounds (mismo valor que usara AuthService via
-- BCRYPT_SALT_ROUNDS).
IF NOT EXISTS (SELECT 1 FROM security.[User] WHERE Username = 'admin')
BEGIN
    INSERT INTO security.[User] (Username, Email, PasswordHash, FullName, IsActive)
    VALUES (
        'admin',
        'admin@biometric.local',
        '$2a$10$61vR/CFf/pUa/NnkoS8UmeMWVvNwbdaDkoZR5pmx5UH3j6RzKJDz2',
        'Administrador Inicial',
        1
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM security.UserRole ur
    INNER JOIN security.[User] u ON u.Id = ur.UserId
    INNER JOIN security.Role r ON r.Id = ur.RoleId
    WHERE u.Username = 'admin' AND r.Name = 'Admin'
)
BEGIN
    INSERT INTO security.UserRole (UserId, RoleId)
    SELECT u.Id, r.Id FROM security.[User] u, security.Role r
    WHERE u.Username = 'admin' AND r.Name = 'Admin';
END
GO

-- 8) Verificacion rapida ---------------------------------------------------
SELECT u.Username, u.Email, u.IsActive, r.Name AS Role
FROM security.[User] u
INNER JOIN security.UserRole ur ON ur.UserId = u.Id
INNER JOIN security.Role r ON r.Id = ur.RoleId;
GO

PRINT 'Fase 2 completa: tablas de security creadas y sembradas.';
GO
