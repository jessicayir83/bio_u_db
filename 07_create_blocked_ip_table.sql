/*
==================================================================
 Bio U - Fase 9 (auditoria)
 Script: Bloqueo manual de IPs (schema `security`)
==================================================================
 Ejecutar contra BiometricPlatformDB DESPUES del script
 06_create_audit_tables.sql.

 Este script es idempotente: puede ejecutarse varias veces sin
 error si los objetos ya existen.

 Un Admin bloquea una IP desde el dashboard de auditoria, SOLO a
 partir de una alerta de intentos fallidos/alarmantes (no por
 escaneo de rutas). Mientras el bloqueo este activo, el API
 rechaza con 403 cualquier request de esa IP.

 Historial: nunca se borra una fila. Desbloquear (o que venza el
 plazo) completa UnblockedAt; un bloqueo nuevo de la misma IP es
 una fila nueva. Solo puede haber UN bloqueo activo por IP (indice
 unico filtrado).

 Sin FOREIGN KEY a security.[User] ni a audit.AuditEvent: se
 guardan ids y username como columnas simples (mismo criterio que
 la bitacora).

 Desbloqueo de emergencia (ej. si un Admin quedo afuera):
   UPDATE security.BlockedIp
   SET UnblockedAt = SYSUTCDATETIME(), UnblockedByUsername = N'dba', UnblockReason = N'Desbloqueo manual por SQL'
   WHERE IpAddress = N'x.x.x.x' AND UnblockedAt IS NULL;
 (el API toma el cambio en menos de 1 minuto)
==================================================================
*/

USE BiometricPlatformDB;
GO

IF OBJECT_ID(N'security.BlockedIp', N'U') IS NULL
BEGIN
    CREATE TABLE security.BlockedIp (
        Id                   INT IDENTITY(1,1) NOT NULL,
        IpAddress            NVARCHAR(64)       NOT NULL,
        Reason               NVARCHAR(500)      NOT NULL,
        SourceAuditEventId   BIGINT             NULL,       -- alerta desde la que se bloqueo
        SourceEventType      NVARCHAR(80)       NULL,
        BlockedByUserId      INT                NOT NULL,
        BlockedByUsername    NVARCHAR(100)      NOT NULL,
        BlockedAt            DATETIME2(3)       NOT NULL CONSTRAINT DF_BlockedIp_BlockedAt DEFAULT (SYSUTCDATETIME()),
        ExpiresAt            DATETIME2(3)       NULL,       -- NULL = sin vencimiento
        UnblockedAt          DATETIME2(3)       NULL,       -- NULL = bloqueo activo (si no vencio)
        UnblockedByUserId    INT                NULL,
        UnblockedByUsername  NVARCHAR(100)      NULL,
        UnblockReason        NVARCHAR(500)      NULL,
        CONSTRAINT PK_BlockedIp PRIMARY KEY CLUSTERED (Id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_BlockedIp_Active' AND object_id = OBJECT_ID('security.BlockedIp'))
    CREATE UNIQUE INDEX UX_BlockedIp_Active ON security.BlockedIp(IpAddress) WHERE UnblockedAt IS NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_BlockedIp_BlockedAt' AND object_id = OBJECT_ID('security.BlockedIp'))
    CREATE INDEX IX_BlockedIp_BlockedAt ON security.BlockedIp(BlockedAt DESC);
GO

PRINT 'Fase 9: security.BlockedIp creada.';
GO
