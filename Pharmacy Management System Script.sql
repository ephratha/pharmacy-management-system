CREATE DATABASE [Pharmacy Management System];
USE [Pharmacy Management System];

-- 1. Create Tables

CREATE TABLE Medicine (
    Med_ID INT IDENTITY(1,1) PRIMARY KEY,
    Name VARCHAR(100) NOT NULL,
    Quantity INT NOT NULL,
    Price DECIMAL(10,2) NOT NULL,
    Expiry_Date DATE NOT NULL,
    Last_Sold DATETIME
);

CREATE TABLE Customer (
    Cust_ID INT IDENTITY(1,1) PRIMARY KEY,
    Name VARCHAR(100) NOT NULL,
    Contact VARCHAR(20) NOT NULL
);

CREATE TABLE Sales (
    Sale_ID INT IDENTITY(1,1) PRIMARY KEY,
    Med_ID INT NOT NULL,
    Cust_ID INT NOT NULL,
    Quantity_Sold INT NOT NULL,
    Sale_Date DATETIME NOT NULL DEFAULT GETDATE(),
    FOREIGN KEY (Med_ID) REFERENCES Medicine(Med_ID),
    FOREIGN KEY (Cust_ID) REFERENCES Customer(Cust_ID)
);

CREATE TABLE StockAlert (
    Alert_ID INT IDENTITY(1,1) PRIMARY KEY,
    Med_ID INT NOT NULL,
    Alert_Msg VARCHAR(255) NOT NULL,
    Alert_Date DATETIME NOT NULL DEFAULT GETDATE(),
    FOREIGN KEY (Med_ID) REFERENCES Medicine(Med_ID)
);

-- we used no foreign keys here to preserve logs even after original data is deleted. however, this log table is still going to be logically linked to ;other tables (as seen in the ERD in the report)
CREATE TABLE SalesLog (
    Log_ID INT IDENTITY(1,1) PRIMARY KEY,
    Sale_ID INT,
    Med_ID INT,
    Cust_ID INT,
    Quantity_Sold INT,
    Sale_Time DATETIME DEFAULT GETDATE(),
    Log_Action VARCHAR(50) NOT NULL,
    Log_Description VARCHAR(255)
);

-- indexes are inserted on the mostly queried fields for query optimization
CREATE INDEX IDX_Sales_MedID ON Sales (Med_ID);
CREATE INDEX IDX_Sales_CustID ON Sales (Cust_ID);
CREATE INDEX IDX_Medicine_ExpiryDate ON Medicine (Expiry_Date);
CREATE INDEX IDX_StockAlert_MedID ON StockAlert (Med_ID);
CREATE INDEX IDX_SalesLog_SaleID ON SalesLog (Sale_ID);
CREATE INDEX IDX_SalesLog_MedID ON SalesLog (Med_ID);
CREATE INDEX IDX_SalesLog_CustID ON SalesLog (Cust_ID);

GO

-- we are inserting update statistics statements to support query optimizers in choosing efficient plans and this section should be executed periodically by the programmer
UPDATE STATISTICS Medicine;
UPDATE STATISTICS Sales;
UPDATE STATISTICS StockAlert;
UPDATE STATISTICS SalesLog;
UPDATE STATISTICS Customer;

GO

-- Inserting sample data into Medicine table
INSERT INTO Medicine (Name, Quantity, Price, Expiry_Date) VALUES
('Aspirin', 100, 5.99, '2028-12-31'),
('Amoxicillin', 23, 12.50, '2030-06-30'),
('Paracetamol', 200, 3.75, '2027-03-15'),
('Ibuprofen', 15, 9.99, '2023-01-01'); -- this medicine has already expired so it will be cleared up from the stock and the sale will be prevented by the triggers

-- Inserting sample data into Customer table
INSERT INTO Customer (Name, Contact) VALUES
('Abebe Bekele', '0997586356'),
('Shimelis Sileshi', '0946825462'),
('Tsehay Berhan', '0943885462'),
('Abeba Desalegn', '0936257684');

-- Inserting sample data into Sales table
INSERT INTO Sales (Med_ID, Cust_ID, Quantity_Sold) VALUES
(1, 1, 5), -- Aspirin sold to Abebe Bekele
(2, 2, 8), -- Amoxicillin sold to Shimelis Sileshi (this entry will later be deleted manually by the transaction 1 because of a refund)
(3, 4, 10), -- Paracetamol sold to Abeba Desalegn
(4, 3, 1),  -- Ibuprofen sold to Tsehay Berhan (this will be prevented by trigger 2 because the Ibuprofen is expired)
(2, 1, 9); -- Amoxicillin sold to Abebe Bekele

-- we have not inserted sample data into the tables SalesLog and StockAlert because these tables are going to be populated primarily by the triggers so we think it is better to leave them empty for better demonstration
-- we also have executed all the transactions, fired the triggers, and used the function and stored procedure so you can see the chnages in the tables from the values inserted
-- 2. Triggers

GO

-- Trigger 1: Low Stock Alert
CREATE TRIGGER TR_Medicine_LowStock
ON Medicine
AFTER INSERT, UPDATE
AS
BEGIN
    BEGIN TRY
        IF EXISTS (SELECT 1 FROM inserted WHERE quantity < 10)
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM StockAlert WHERE Med_ID = (SELECT Med_ID FROM inserted) AND Alert_Msg = CONCAT('Stock of ',(SELECT Name from inserted),' is below 10 units with ',(SELECT Quantity from inserted),' remaining!'))
            BEGIN
                INSERT INTO StockAlert (Med_ID, Alert_Msg, Alert_Date)
                SELECT Med_ID,CONCAT('Stock of ',Name,' is below 10 units with only ',Quantity,' remaining!'), GETDATE()
                FROM inserted
                WHERE quantity < 10;
            END
        END
    END TRY
    BEGIN CATCH
        PRINT 'Error in TR_Medicine_LowStock: ' + ERROR_MESSAGE();
    END CATCH;
END;

GO

-- Trigger 2: Prevent Sale of Expired Medicine
CREATE TRIGGER TR_Sales_PreventExpired
ON Sales
INSTEAD OF INSERT
AS
BEGIN
    BEGIN TRY
        IF EXISTS (
            SELECT 1 FROM inserted i
            JOIN Medicine m ON i.med_id = m.Med_ID
            WHERE m.Expiry_Date < GETDATE()
        )
        BEGIN
            PRINT 'Cannot sell expired medicine.';
            RETURN;
        END

        INSERT INTO Sales (Med_ID, Cust_ID, Quantity_Sold, Sale_Date)
        SELECT Med_ID, Cust_ID, Quantity_Sold, Sale_Date FROM inserted;
    END TRY
    BEGIN CATCH
        PRINT 'Error in TR_Sales_PreventExpired: ' + ERROR_MESSAGE();
    END CATCH;
END;

GO

-- Trigger 3: Log Entry Insert
CREATE TRIGGER TR_Sales_Insert
ON Sales
AFTER INSERT
AS
BEGIN
    BEGIN TRY
        INSERT INTO SalesLog (Sale_ID, Med_ID, Cust_ID, Quantity_Sold, Sale_Time, Log_Action)
        SELECT i.Sale_ID, i.Med_ID, i.Cust_ID, i.Quantity_Sold, GETDATE(), 'Insert'
        FROM inserted i;
    END TRY
    BEGIN CATCH
        PRINT 'Error in TR_Sales_Insert: ' + ERROR_MESSAGE();
    END CATCH;
END;

GO

-- Trigger 4: Log Entry Update
CREATE TRIGGER TR_Sales_Update
ON Sales
AFTER UPDATE
AS
BEGIN
    BEGIN TRY
        INSERT INTO SalesLog (Sale_ID, Med_ID, Cust_ID, Quantity_Sold, Sale_Time, Log_Action)
        SELECT i.Sale_ID, i.Med_ID, i.Cust_ID, i.Quantity_Sold, GETDATE(), 'Update'
        FROM inserted i;
    END TRY
    BEGIN CATCH
        PRINT 'Error in TR_Sales_Update: ' + ERROR_MESSAGE();
    END CATCH;
END;

GO

-- Trigger 5: Log Entry Delete
CREATE TRIGGER TR_Sales_Delete
ON Sales
INSTEAD OF DELETE
AS
BEGIN
    BEGIN TRY
        INSERT INTO SalesLog (Sale_ID, Med_ID, Cust_ID, Quantity_Sold, Sale_Time, Log_Action)
        SELECT d.Sale_ID, d.Med_ID, d.Cust_ID, d.Quantity_Sold, GETDATE(), 'Delete'
        FROM deleted d;

        DELETE FROM Sales WHERE Sale_ID IN (SELECT Sale_ID FROM deleted);
    END TRY
    BEGIN CATCH
        PRINT 'Error in TR_Sales_Delete: ' + ERROR_MESSAGE();
    END CATCH;
END;

GO

-- 3. Transactions

-- Transaction 1: Refund Processing
DECLARE @Refund_Sale_ID INT = 2;

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN TRANSACTION;

    IF EXISTS (SELECT 1 FROM Sales WHERE Sale_ID = @Refund_Sale_ID)
    BEGIN
        IF (SELECT COUNT(*) FROM Sales WHERE Sale_ID = @Refund_Sale_ID) = 1
        BEGIN
            DECLARE @Refund_Med_ID INT;
            DECLARE @Refund_Qty INT;

            SELECT @Refund_Med_ID = Med_ID, @Refund_Qty = Quantity_Sold
            FROM Sales
            WHERE Sale_ID = @Refund_Sale_ID;

            DELETE FROM Sales WHERE Sale_ID = @Refund_Sale_ID;

			UPDATE Medicine
            SET Quantity = Quantity + @Refund_Qty
            WHERE Med_ID = @Refund_Med_ID;
        END
        ELSE
        BEGIN
            PRINT 'Multiple sales exist for Sale_ID = ' + CAST(@Refund_Sale_ID AS VARCHAR(10)) + '. Refund cannot proceed.';
        END
    END
    ELSE
    BEGIN
        PRINT 'Sale_ID = ' + CAST(@Refund_Sale_ID AS VARCHAR(10)) + ' does not exist. Refund cannot proceed.';
    END

    COMMIT;
-- as mentioned earlier, this refunds the Sales entry with ID Sales_ID 2 (Amoxicillin sold to Shimelis Sileshi)

GO

-- Transaction 2: Expired Medicine Cleanup
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN TRANSACTION;
BEGIN TRY
    DELETE FROM SalesLog 
    WHERE Med_ID IN (SELECT Med_ID FROM Medicine WHERE Expiry_Date < GETDATE());

    DELETE FROM Sales 
    WHERE Med_ID IN (SELECT Med_ID FROM Medicine WHERE Expiry_Date < GETDATE());

    DELETE FROM Medicine 
    WHERE Expiry_Date < GETDATE();

    COMMIT;
END TRY
BEGIN CATCH
    ROLLBACK;
    PRINT 'Error during cleanup: ' + ERROR_MESSAGE();
END CATCH;
-- as mentioned earlier, this stops/deletes the Sales entry with ID Sales_ID 4 (Ibuprofen sold to Tsehay Berhan) and also deletes the record of the medicine because it is expired

GO

-- 4. Stored Procedure

CREATE PROCEDURE SP_AddSale
    @Med_ID INT, @Cust_ID INT, @Qty INT
AS
BEGIN
    BEGIN TRANSACTION;
    BEGIN TRY
        IF EXISTS (
            SELECT 1 FROM Medicine WHERE Med_ID = @Med_ID AND Expiry_Date >= GETDATE() AND Quantity >= @Qty
        )
        BEGIN
            INSERT INTO Sales (Med_ID, Cust_ID, Quantity_Sold, Sale_Date)
            VALUES (@Med_ID, @Cust_ID, @Qty, GETDATE());

            UPDATE Medicine
            SET Quantity = Quantity - @Qty, Last_Sold = GETDATE()
            WHERE Med_ID = @Med_ID;

            COMMIT TRANSACTION;
        END
        ELSE
        BEGIN
            ROLLBACK TRANSACTION;
            PRINT 'Expired, insufficient stock or invalid medicine.';
        END
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        PRINT 'Error in SP_AddSale: ' + ERROR_MESSAGE();
    END CATCH;
END;
-- if we use this stored procedure to make a sale that would leave the stock of a medicine below 10, it will insert an alert entry into the StockAlert table.
-- this alert will be inserted mainly by the work of trigger 1
-- example: EXEC SP_AddSale @Med_ID = 2, @Cust_ID = 1, @Qty = 19; try to run this example and see how the StocksAlert table will be updated by trigger 1

GO

-- 5. Function

CREATE FUNCTION FN_CheckAvailability(@Med_ID INT)
RETURNS INT
AS
BEGIN
    DECLARE @Stock INT;

    IF EXISTS (SELECT 1 FROM Medicine WHERE Med_ID = @Med_ID)
    BEGIN
        SELECT @Stock = Quantity FROM Medicine WHERE Med_ID = @Med_ID;
    END
    ELSE
    BEGIN
        SET @Stock = 0;
    END

    RETURN @Stock;
END;
--example: SELECT 
    --			m.Med_ID,
    --			m.Name,
    --			dbo.FN_CheckAvailability(m.Med_ID) AS Available_Stock
	--	   FROM Medicine m;
-- try to execute this example code to see how the function works. it will return back the remaining amount of all medicines
GO

-- 6. Backup and Restore Commands

BEGIN TRY
    BACKUP DATABASE [Pharmacy Management System] TO DISK = 'C:\Backups\PharmacyDB.bak' WITH INIT; -- you have to make sure this path exists first
    PRINT 'Backup completed successfully.';
END TRY
BEGIN CATCH
    PRINT 'Backup failed: ' + ERROR_MESSAGE();
END CATCH;
BEGIN TRY
    RESTORE DATABASE [Pharmacy Management System] FROM DISK = 'C:\Backups\PharmacyDB.bak' WITH REPLACE;
    PRINT 'Restore completed successfully.';
END TRY
BEGIN CATCH
    PRINT 'Restore failed: ' + ERROR_MESSAGE();
END CATCH;


-- 7. Security

CREATE LOGIN pharmacy_user WITH PASSWORD = 'iAmThePharmacist!' -- this is a sample password so you can change it however you want
CREATE USER pharmacy_user FOR LOGIN pharmacy_user;
GRANT SELECT, INSERT ON Sales TO pharmacy_user;
GRANT SELECT ON Medicine TO pharmacy_user;
GRANT EXECUTE ON SP_AddSale TO pharmacy_user;
-- after you execute this, you can see how it works by enabling SQL Server Authentication
