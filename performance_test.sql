USE TestDB;
GO

-- 清理現有的存儲過程
IF OBJECT_ID('PerformanceTest', 'P') IS NOT NULL
    DROP PROCEDURE PerformanceTest;
GO

IF OBJECT_ID('ConcurrentOperationsTest', 'P') IS NOT NULL
    DROP PROCEDURE ConcurrentOperationsTest;
GO

IF OBJECT_ID('GenerateTestData', 'P') IS NOT NULL
    DROP PROCEDURE GenerateTestData;
GO

-- 創建測試數據生成存儲過程
CREATE PROCEDURE GenerateTestData
    @RecordCount INT
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        -- 清理現有數據
        DELETE FROM Customers;
        
        DECLARE @Counter INT = 1;
        DECLARE @BatchSize INT = 1000;
        DECLARE @StartTime DATETIME2 = SYSDATETIME();
        
        WHILE @Counter <= @RecordCount
        BEGIN
            INSERT INTO Customers (Name, Email, CreatedAt)
            SELECT 
                N'用戶' + CAST(number AS NVARCHAR(20)),
                'user' + CAST(number AS NVARCHAR(20)) + '@example.com',
                GETDATE()
            FROM master.dbo.spt_values
            WHERE type = 'P'
                AND number BETWEEN @Counter AND @Counter + @BatchSize - 1
                AND number <= @RecordCount;
                
            SET @Counter = @Counter + @BatchSize;
            
            -- 每10000條記錄輸出一次進度
            IF @Counter % 10000 = 0
                PRINT '已生成 ' + CAST(@Counter AS VARCHAR(20)) + ' 條記錄';
        END;
        
        DECLARE @EndTime DATETIME2 = SYSDATETIME();
        DECLARE @Duration DECIMAL(10, 2) = DATEDIFF(MILLISECOND, @StartTime, @EndTime) / 1000.0;
        
        PRINT '數據生成完成。總時間: ' + CAST(@Duration AS VARCHAR(20)) + ' 秒';
    END TRY
    BEGIN CATCH
        PRINT '錯誤: ' + ERROR_MESSAGE();
        THROW;
    END CATCH
END;
GO

-- 創建並發操作測試存儲過程
CREATE PROCEDURE ConcurrentOperationsTest
    @OperationCount INT
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        DECLARE @Counter INT = 1;
        DECLARE @RandomId INT;
        DECLARE @MaxId INT;
        DECLARE @StartTime DATETIME2 = SYSDATETIME();
        DECLARE @InsertCount INT = 0;
        DECLARE @UpdateCount INT = 0;
        DECLARE @DeleteCount INT = 0;
        
        -- 獲取最大ID
        SELECT @MaxId = MAX(CustomerId) FROM Customers;
        
        IF @MaxId IS NULL
        BEGIN
            RAISERROR ('Customers表中沒有記錄', 16, 1);
            RETURN;
        END;
        
        WHILE @Counter <= @OperationCount
        BEGIN
            -- 隨機選擇操作類型（1：插入，2：更新，3：刪除）
            DECLARE @Operation INT = CAST(RAND() * 3 + 1 AS INT);
            
            BEGIN TRY
                IF @Operation = 1 -- 插入
                BEGIN
                    INSERT INTO Customers (Name, Email, CreatedAt)
                    VALUES (N'新用戶' + CAST(@Counter AS NVARCHAR(20)),
                           'newuser' + CAST(@Counter AS NVARCHAR(20)) + '@example.com',
                           GETDATE());
                    SET @InsertCount = @InsertCount + 1;
                END
                ELSE IF @Operation = 2 -- 更新
                BEGIN
                    SET @RandomId = CAST(RAND() * @MaxId + 1 AS INT);
                    UPDATE TOP(1) Customers
                    SET Email = 'updated' + CAST(@Counter AS NVARCHAR(20)) + '@example.com',
                        CreatedAt = GETDATE()
                    WHERE CustomerId >= @RandomId;
                    SET @UpdateCount = @UpdateCount + 1;
                END
                ELSE -- 刪除
                BEGIN
                    SET @RandomId = CAST(RAND() * @MaxId + 1 AS INT);
                    DELETE TOP(1) FROM Customers
                    WHERE CustomerId >= @RandomId;
                    SET @DeleteCount = @DeleteCount + 1;
                END
            END TRY
            BEGIN CATCH
                -- 記錄錯誤但繼續執行
                PRINT '操作 ' + CAST(@Counter AS VARCHAR(10)) + ' 失敗: ' + ERROR_MESSAGE();
            END CATCH
            
            SET @Counter = @Counter + 1;
            
            -- 每1000次操作輸出一次進度
            IF @Counter % 1000 = 0
                PRINT '已完成 ' + CAST(@Counter AS VARCHAR(10)) + ' 次操作';
        END;
        
        DECLARE @EndTime DATETIME2 = SYSDATETIME();
        DECLARE @Duration DECIMAL(10, 2) = DATEDIFF(MILLISECOND, @StartTime, @EndTime) / 1000.0;
        
        -- 輸出詳細的操作統計
        PRINT '操作統計:';
        PRINT '總操作數: ' + CAST(@OperationCount AS VARCHAR(10));
        PRINT '插入操作: ' + CAST(@InsertCount AS VARCHAR(10));
        PRINT '更新操作: ' + CAST(@UpdateCount AS VARCHAR(10));
        PRINT '刪除操作: ' + CAST(@DeleteCount AS VARCHAR(10));
        PRINT '總耗時: ' + CAST(@Duration AS VARCHAR(20)) + ' 秒';
        PRINT '平均每次操作耗時: ' + CAST(@Duration / @OperationCount AS VARCHAR(20)) + ' 秒';
        
        -- 返回統計數據
        SELECT 
            @OperationCount AS TotalOperations,
            @InsertCount AS InsertCount,
            @UpdateCount AS UpdateCount,
            @DeleteCount AS DeleteCount,
            @Duration AS DurationSeconds,
            @Duration / @OperationCount AS AvgOperationSeconds;
    END TRY
    BEGIN CATCH
        PRINT '錯誤: ' + ERROR_MESSAGE();
        THROW;
    END CATCH
END;
GO

-- 修改 PerformanceTest 存儲過程
CREATE PROCEDURE PerformanceTest
    @InitialDataSize INT = 10000,    -- 初始數據量（預設1萬）
    @OperationCount INT = 5000,       -- 測試操作數量
    @CleanupData BIT = 0               -- 是否清理數據，預設不清理
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        -- 檢查CDC狀態
        DECLARE @IsCdcEnabled BIT;
        SELECT @IsCdcEnabled = is_tracked_by_cdc
        FROM sys.tables
        WHERE object_id = OBJECT_ID('Customers');
        
        PRINT '當前CDC狀態: ' + CASE WHEN @IsCdcEnabled = 1 THEN '啟用' ELSE '禁用' END;
        
        -- 檢查現有數據量
        DECLARE @ExistingCount INT;
        SELECT @ExistingCount = COUNT(*) FROM Customers;
        
        -- 如果數據量不足，則生成更多數據
        IF @ExistingCount < @InitialDataSize
        BEGIN
            DECLARE @NeededCount INT = @InitialDataSize - @ExistingCount;
            PRINT '現有數據量: ' + CAST(@ExistingCount AS VARCHAR(20));
            PRINT '需要生成額外數據量: ' + CAST(@NeededCount AS VARCHAR(20));
            
            EXEC GenerateTestData @NeededCount;
            
            -- 重新獲取數據量
            SELECT @ExistingCount = COUNT(*) FROM Customers;
        END

        PRINT '當前總數據量: ' + CAST(@ExistingCount AS VARCHAR(20));
        
        -- 等待系統穩定
        WAITFOR DELAY '00:00:02';
        
        -- 記錄開始時間
        DECLARE @StartTime DATETIME2 = SYSDATETIME();
        
        -- 執行並發操作測試
        PRINT '開始執行並發操作測試...';
        EXEC ConcurrentOperationsTest @OperationCount;
        
        -- 記錄操作時間
        DECLARE @OperationsTime DECIMAL(10, 2) = DATEDIFF(MILLISECOND, @StartTime, SYSDATETIME()) / 1000.0;
        
        -- 輸出性能指標
        SELECT 
            CASE WHEN @IsCdcEnabled = 1 THEN 'Enabled' ELSE 'Disabled' END AS CDC_Status,
            @ExistingCount AS TotalRecords,
            @OperationCount AS TestOperations,
            @OperationsTime AS TotalTimeSeconds,
            CAST(@OperationsTime / CAST(@OperationCount AS FLOAT) AS DECIMAL(10, 4)) AS AvgOperationTimeSeconds;
            
        -- 如果需要清理數據
        IF @CleanupData = 1
        BEGIN
            PRINT '清理測試數據...';
            DELETE FROM Customers;
        END
    END TRY
    BEGIN CATCH
        PRINT '錯誤: ' + ERROR_MESSAGE();
        THROW;
    END CATCH
END;
GO