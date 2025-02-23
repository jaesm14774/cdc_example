-- 创建数据库
CREATE DATABASE TestDB;
GO

USE TestDB;
GO

-- 启用 CDC
EXEC sys.sp_cdc_enable_db;
GO

-- 创建示例表
CREATE TABLE Customers (
    CustomerId INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100),
    Email NVARCHAR(100),
    CreatedAt DATETIME DEFAULT GETDATE()
);
GO

-- 为表启用 CDC
EXEC sys.sp_cdc_enable_table
    @source_schema = N'dbo',
    @source_name = N'Customers',
    @role_name = NULL,
    @supports_net_changes = 1;
GO

-- 插入示例数据
INSERT INTO Customers (Name, Email) VALUES
    (N'张三', 'zhangsan@example.com'),
    (N'李四', 'lisi@example.com'),
    (N'王五', 'wangwu@example.com');
GO