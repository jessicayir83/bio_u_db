/*
==================================================================
 Bio U - Templates adaptativos y registro guiado (Nivel 2 facial)
==================================================================
 Ejecutar contra BiometricPlatformDB DESPUES del script
 08_identification_type_registrations_scans.sql.

 Este script es idempotente: puede ejecutarse varias veces sin
 error (cada paso verifica si ya se aplico). Cada paso va en su
 propio lote (GO) porque SQL Server no deja usar una columna nueva
 en el mismo lote en que se crea.

 Por que: hasta ahora biometric.Template solo guardaba el vector y
 la fecha. No habia forma de saber de donde salio cada vector, con
 que detector se genero, ni de dar de baja uno malo sin borrarlo.
 Eso bloqueaba las dos mitades del Nivel 2:

 1. Registro guiado: cada foto del registro corresponde a un paso
    de pose (FRONT / LEFT / RIGHT). Guardarlo permite ver si una
    persona tiene galeria variada o tres fotos frontales iguales.
 2. Templates adaptativos: el sistema agrega vectores solo, a
    partir de ingresos reconocidos con holgura. Hay que poder
    distinguirlos de los del registro (Source), limitarlos por
    persona (MatchCount / LastMatchedAt para decidir cual se
    descarta al llegar al tope) y revertirlos (RevokedAt).

 Cambios:
 1. biometric.Template.Source: ENROLLMENT | ADAPTIVE. Las filas
    existentes quedan como ENROLLMENT.
 2. biometric.Template.Detector: ssd | tiny | NULL (desconocido,
    para las filas anteriores a este script). Cambiar el detector
    altera los descriptores ~0.15-0.2, asi que saber con cual se
    genero cada template es lo que permite detectar los viejos.
 3. biometric.Template.PoseStep: paso del registro guiado.
 4. Metricas de la captura (DetectionScore, YawOffset, Sharpness)
    para calibrar y para mostrar la calidad en el panel.
 5. Uso (MatchCount, LastMatchedAt): cuantas veces sirvio cada
    template. Alimenta la politica de descarte al llegar al tope.
 6. Revocacion logica (RevokedAt, RevokedByUserId, RevokedReason):
    un template revocado deja de usarse para reconocer, pero el
    vector NO se borra. RevokedByUserId es columna simple, sin FK
    ni relacion TypeORM a security.[User].
 7. Trazabilidad del adaptativo (SourceAccessLogId, SourceDistance):
    de que escaneo salio y con que distancia se acepto.
 8. Indices para la consulta del 1:N (que corre en cada ingreso) y
    para el tope por persona.

 Nota: la columna Vector sigue cifrada (AES-256-GCM, Fase 7). Este
 script no la toca.

 Importante: el API ya espera estas columnas. Hasta ejecutar el
 script, el reconocimiento y el enrollment fallan (columnas
 inexistentes).
==================================================================
*/

USE BiometricPlatformDB;
GO

-- 1. Procedencia del template ----------------------------------------------
IF COL_LENGTH('biometric.Template', 'Source') IS NULL
    ALTER TABLE biometric.Template
        ADD Source NVARCHAR(20) NOT NULL
            CONSTRAINT DF_Template_Source DEFAULT (N'ENROLLMENT') WITH VALUES;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Template_Source')
    ALTER TABLE biometric.Template
        ADD CONSTRAINT CK_Template_Source CHECK (Source IN (N'ENROLLMENT', N'ADAPTIVE'));
GO

-- 2. Detector con el que se genero el vector -------------------------------
-- NULL = generado antes de este script (no se puede saber cual fue).
IF COL_LENGTH('biometric.Template', 'Detector') IS NULL
    ALTER TABLE biometric.Template ADD Detector NVARCHAR(10) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Template_Detector')
    ALTER TABLE biometric.Template
        ADD CONSTRAINT CK_Template_Detector CHECK (Detector IS NULL OR Detector IN (N'ssd', N'tiny'));
GO

-- 3. Paso del registro guiado ----------------------------------------------
-- NULL = captura no guiada (registro viejo, subida de archivo, adaptativo).
IF COL_LENGTH('biometric.Template', 'PoseStep') IS NULL
    ALTER TABLE biometric.Template ADD PoseStep NVARCHAR(20) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Template_PoseStep')
    ALTER TABLE biometric.Template
        ADD CONSTRAINT CK_Template_PoseStep CHECK (PoseStep IS NULL OR PoseStep IN (N'FRONT', N'LEFT', N'RIGHT'));
GO

-- 4. Metricas de calidad del momento de la captura -------------------------
IF COL_LENGTH('biometric.Template', 'DetectionScore') IS NULL
    ALTER TABLE biometric.Template ADD DetectionScore FLOAT NULL;
GO

IF COL_LENGTH('biometric.Template', 'YawOffset') IS NULL
    ALTER TABLE biometric.Template ADD YawOffset FLOAT NULL;
GO

IF COL_LENGTH('biometric.Template', 'Sharpness') IS NULL
    ALTER TABLE biometric.Template ADD Sharpness FLOAT NULL;
GO

-- 5. Uso: cuantas veces este template fue el mas cercano en un match -------
IF COL_LENGTH('biometric.Template', 'MatchCount') IS NULL
    ALTER TABLE biometric.Template
        ADD MatchCount INT NOT NULL
            CONSTRAINT DF_Template_MatchCount DEFAULT (0) WITH VALUES;
GO

IF COL_LENGTH('biometric.Template', 'LastMatchedAt') IS NULL
    ALTER TABLE biometric.Template ADD LastMatchedAt DATETIME2 NULL;
GO

-- 6. Revocacion logica -----------------------------------------------------
-- Un template revocado no se usa para reconocer, pero el vector se conserva
-- (misma logica que el soft delete de Persons/Users: nunca se borra biometria).
IF COL_LENGTH('biometric.Template', 'RevokedAt') IS NULL
    ALTER TABLE biometric.Template ADD RevokedAt DATETIME2 NULL;
GO

IF COL_LENGTH('biometric.Template', 'RevokedByUserId') IS NULL
    ALTER TABLE biometric.Template ADD RevokedByUserId INT NULL;
GO

IF COL_LENGTH('biometric.Template', 'RevokedReason') IS NULL
    ALTER TABLE biometric.Template ADD RevokedReason NVARCHAR(200) NULL;
GO

-- 7. Trazabilidad del template adaptativo ----------------------------------
-- De que escaneo salio y con que distancia se acepto. Es lo que permite
-- reconstruir hacia atras un envenenamiento: que ingreso, desde que IP, a
-- que hora y con que distancia genero cada vector aprendido.
IF COL_LENGTH('biometric.Template', 'SourceAccessLogId') IS NULL
    ALTER TABLE biometric.Template ADD SourceAccessLogId INT NULL;
GO

IF COL_LENGTH('biometric.Template', 'SourceDistance') IS NULL
    ALTER TABLE biometric.Template ADD SourceDistance FLOAT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Template_SourceAccessLog')
    ALTER TABLE biometric.Template
        ADD CONSTRAINT FK_Template_SourceAccessLog
            FOREIGN KEY (SourceAccessLogId) REFERENCES biometric.AccessLog(Id);
GO

-- Solo los adaptativos pueden tener origen: un template de registro no sale
-- de un escaneo.
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Template_AdaptiveSource')
    ALTER TABLE biometric.Template
        ADD CONSTRAINT CK_Template_AdaptiveSource
            CHECK (Source = N'ADAPTIVE' OR (SourceAccessLogId IS NULL AND SourceDistance IS NULL));
GO

-- No se puede tener revocador sin revocacion (al reves si: la revocacion
-- automatica por tope no tiene usuario).
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Template_Revocation')
    ALTER TABLE biometric.Template
        ADD CONSTRAINT CK_Template_Revocation
            CHECK (RevokedByUserId IS NULL OR RevokedAt IS NOT NULL);
GO

-- 8. Indices ---------------------------------------------------------------
-- La identificacion 1:N lee todos los templates activos de una modalidad en
-- cada ingreso del kiosco: indice filtrado por los no revocados.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Template_Modality_Active' AND object_id = OBJECT_ID('biometric.Template'))
    CREATE INDEX IX_Template_Modality_Active
        ON biometric.Template(Modality)
        INCLUDE (PersonId, Source)
        WHERE RevokedAt IS NULL;
GO

-- Tope de templates por persona y galeria del panel.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Template_PersonId_Source' AND object_id = OBJECT_ID('biometric.Template'))
    CREATE INDEX IX_Template_PersonId_Source ON biometric.Template(PersonId, Source);
GO

PRINT 'Script 09 aplicado: biometric.Template listo para templates adaptativos y registro guiado.';
GO
