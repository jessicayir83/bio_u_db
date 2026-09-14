USE master;
GO

CREATE LOGIN BiometricPlatformUser
WITH PASSWORD = 'TuPasswordSeguraAqui123!';
GO

USE BiometricPlatformDB;
GO

CREATE USER BiometricPlatformUser
FOR LOGIN BiometricPlatformUser;
GO

USE BiometricPlatformDB;
GO

ALTER ROLE db_owner
ADD MEMBER BiometricPlatformUser;
GO

ALTER LOGIN BiometricPlatformUser
WITH PASSWORD = 'BioU9826%&**!';
GO