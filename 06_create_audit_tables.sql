/*
==================================================================
 Bio U - Fase 9 (auditoria)
 Script: Bitacora de auditoria (schema `audit`)
==================================================================
 Ejecutar contra BiometricPlatformDB DESPUES del script
 05_create_access_log_table.sql.

 Este script es idempotente: puede ejecutarse varias veces sin
 error si los objetos ya existen.

 Que se registra: TODO lo que pasa en el API (cada request HTTP,
 logins, cambios de datos, intentos del kiosco, errores, alertas de
 seguridad detectadas y eventos de sistema), clasificado por
 severidad: SEV1 (alerta real), SEV2, SEV3, NORMAL.

 Que NUNCA se registra: contrasenas, tokens, fotos, descriptores
 biometricos, ni valores de datos personales (cedula, nombres,
 fecha de nacimiento). Los cambios sobre personas guardan el id del
 registro y los NOMBRES de los campos modificados, no sus valores.

 Inmutabilidad: audit.AuditEvent es append-only. Un trigger
 INSTEAD OF UPDATE, DELETE rechaza cualquier modificacion o borrado,
 incluso desde el propio API. Una purga por retencion (si algun dia
 se define) es una accion de DBA: deshabilitar el trigger, borrar
 con criterio documentado y volver a habilitarlo.

 Sin FOREIGN KEY a security.[User] a proposito: la bitacora debe
 sobrevivir intacta aunque cambien o se borren usuarios. Por eso
 tambien guarda una copia del username (ActorUsername).
==================================================================
*/

USE BiometricPlatformDB;
GO

IF OBJECT_ID(N'audit.AuditEvent', N'U') IS NULL
BEGIN
    CREATE TABLE audit.AuditEvent (
        Id             BIGINT IDENTITY(1,1) NOT NULL,
        OccurredAt     DATETIME2(3)       NOT NULL CONSTRAINT DF_AuditEvent_OccurredAt DEFAULT (SYSUTCDATETIME()),
        Severity       NVARCHAR(10)       NOT NULL,   -- SEV1 | SEV2 | SEV3 | NORMAL
        Category       NVARCHAR(30)       NOT NULL,   -- AUTH, USER, PERSON, ENROLLMENT, VERIFICATION, KIOSK, SECURITY, AUDIT, SYSTEM, HTTP
        EventType      NVARCHAR(80)       NOT NULL,   -- ej. AUTH_LOGIN_FAILED
        Outcome        NVARCHAR(20)       NOT NULL,   -- SUCCESS | FAILURE | DENIED | ERROR | INFO
        ActorType      NVARCHAR(20)       NOT NULL,   -- USER | ANONYMOUS | SYSTEM
        ActorUserId    INT                NULL,
        ActorUsername  NVARCHAR(100)      NULL,       -- copia al momento del evento (o username intentado en un login fallido)
        SourceIp       NVARCHAR(64)       NULL,
        UserAgent      NVARCHAR(400)      NULL,
        HttpMethod     NVARCHAR(10)       NULL,
        Path           NVARCHAR(400)      NULL,       -- sin query string (las claves van en Details)
        StatusCode     INT                NULL,
        DurationMs     INT                NULL,
        TargetType     NVARCHAR(40)       NULL,       -- ej. Person, User, Enrollment
        TargetId       NVARCHAR(64)       NULL,
        Message        NVARCHAR(1000)     NULL,       -- descripcion legible
        Details        NVARCHAR(MAX)      NULL,       -- JSON saneado (nunca secretos ni biometria)
        CorrelationId  NVARCHAR(64)       NULL,       -- id de request (header X-Request-Id)
        CONSTRAINT PK_AuditEvent PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT CK_AuditEvent_Severity CHECK (Severity IN (N'SEV1', N'SEV2', N'SEV3', N'NORMAL')),
        CONSTRAINT CK_AuditEvent_Outcome CHECK (Outcome IN (N'SUCCESS', N'FAILURE', N'DENIED', N'ERROR', N'INFO')),
        CONSTRAINT CK_AuditEvent_ActorType CHECK (ActorType IN (N'USER', N'ANONYMOUS', N'SYSTEM'))
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AuditEvent_OccurredAt' AND object_id = OBJECT_ID('audit.AuditEvent'))
    CREATE INDEX IX_AuditEvent_OccurredAt ON audit.AuditEvent(OccurredAt DESC) INCLUDE (Severity);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AuditEvent_Severity_OccurredAt' AND object_id = OBJECT_ID('audit.AuditEvent'))
    CREATE INDEX IX_AuditEvent_Severity_OccurredAt ON audit.AuditEvent(Severity, OccurredAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AuditEvent_SourceIp_OccurredAt' AND object_id = OBJECT_ID('audit.AuditEvent'))
    CREATE INDEX IX_AuditEvent_SourceIp_OccurredAt ON audit.AuditEvent(SourceIp, OccurredAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AuditEvent_EventType_OccurredAt' AND object_id = OBJECT_ID('audit.AuditEvent'))
    CREATE INDEX IX_AuditEvent_EventType_OccurredAt ON audit.AuditEvent(EventType, OccurredAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AuditEvent_ActorUserId_OccurredAt' AND object_id = OBJECT_ID('audit.AuditEvent'))
    CREATE INDEX IX_AuditEvent_ActorUserId_OccurredAt ON audit.AuditEvent(ActorUserId, OccurredAt DESC);
GO

-- Append-only: rechaza UPDATE y DELETE ---------------------------------
IF OBJECT_ID(N'audit.TR_AuditEvent_Immutable', N'TR') IS NULL
    EXEC('
    CREATE TRIGGER audit.TR_AuditEvent_Immutable
    ON audit.AuditEvent
    INSTEAD OF UPDATE, DELETE
    AS
    BEGIN
        SET NOCOUNT ON;
        THROW 51000, ''audit.AuditEvent es inmutable (append-only): no se permite modificar ni borrar eventos.'', 1;
    END');
GO

-- Revision de alertas (SEV1/SEV2) ---------------------------------------
-- Separada de AuditEvent para no romper la inmutabilidad: marcar una
-- alerta como revisada agrega una fila aca (y ademas un evento de
-- auditoria AUDIT_ALERT_ACKNOWLEDGED), nunca modifica el evento original.
IF OBJECT_ID(N'audit.AlertAcknowledgement', N'U') IS NULL
BEGIN
    CREATE TABLE audit.AlertAcknowledgement (
        Id                      INT IDENTITY(1,1) NOT NULL,
        AuditEventId            BIGINT             NOT NULL,
        AcknowledgedByUserId    INT                NOT NULL,
        AcknowledgedByUsername  NVARCHAR(100)      NOT NULL,
        Note                    NVARCHAR(500)      NULL,
        AcknowledgedAt          DATETIME2(3)       NOT NULL CONSTRAINT DF_AlertAcknowledgement_At DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_AlertAcknowledgement PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_AlertAcknowledgement_Event UNIQUE (AuditEventId),
        CONSTRAINT FK_AlertAcknowledgement_Event FOREIGN KEY (AuditEventId) REFERENCES audit.AuditEvent(Id)
    );
END
GO

PRINT 'Fase 9: audit.AuditEvent (append-only) y audit.AlertAcknowledgement creadas.';
GO
