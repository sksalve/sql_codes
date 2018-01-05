USE [Fax_Ocean]
GO
/****** Object:  Trigger [dbo].[AddFooterStamp]    Script Date: 01/05/2018 12:36:11 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



-- =============================================
-- Author	: ASHLEY WONG
-- Create date	: 27-APR-2014
-- Modify date  : 29-MAY-2014 (Add check PageCount)
-- Description	: Add FootStamp with S/N, Branch Code
-- =============================================
ALTER TRIGGER [dbo].[AddFooterStamp]
   ON  [dbo].[FM_FaxIn]
   --AFTER UPDATE
   AFTER UPDATE
AS 
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    -- Insert statements for trigger here
		DECLARE @UpdatedFaxInGuid as int
        DECLARE @UpdatedCalledNo as Varchar(64)
        DECLARE @FootStampGuid as int
        DECLARE @Condition as varchar(20)
        DECLARE @Condition1 as varchar(20)
        DECLARE @Condition2 as varchar(20)           
        DECLARE @start INT, @end INT
        DECLARE @count as int
        DECLARE @UpdatedStatus as int
        DECLARE @brcode as nvarchar(50)
        DECLARE @NextResetDate as nvarchar(10)
        DECLARE @NextResetTime as nvarchar(10)
        DECLARE @DateFormat as int
        DECLARE @UpdatedResultCode as varchar(16)
        DECLARE @UpdatedPageCount as int     
		DECLARE @FaxDateTime as datetime --RISPL
        DECLARE @FaxDateTime_Formatted as nvarchar(17) --RISPL
		DECLARE @SyncFieldForLoopback as nvarchar(max)
		DECLARE @ValueForLoopback as nvarchar(max)
		DECLARE @FaxguidNeedUpdate as int
		DECLARE @csn as varchar(32)
		DECLARE @SenderEmail as varchar(50) --ss
		DECLARE @SubjectLine as nvarchar(100)
        
        --CREATEDTIME RISPL
        DECLARE ObsSet_Cursor_FM_FaxIn CURSOR FOR
			SELECT inserted.FaxInGuid, inserted.CalledNo, inserted.status, inserted.ResultCode, inserted.PageCount, inserted.createdtime, inserted.CardSerialNumber
				FROM inserted
		
		--@FAXDATETIME RISPL
		Open ObsSet_Cursor_FM_FaxIn
		FETCH NEXT FROM ObsSet_Cursor_FM_FaxIn INTO @UpdatedFaxInGuid, @UpdatedCalledNo, @UpdatedStatus, @UpdatedResultCode, @UpdatedPageCount, @FaxDateTime, @csn 
        WHILE @@FETCH_STATUS = 0
        BEGIN			
			BEGIN
				SET @FootStampGuid = 0


				--SET @UpdatedCalledNo = '*'
				-- Get is there have any FootStamp setting for currect Ext. number (route number)
				SET @FootStampGuid = (SELECT FootStampGuid FROM CS_FootStamp WITH (NOLOCK) WHERE FaxExtNo = @UpdatedCalledNo)
				
				-- if there have any FootStamp settinf for current ext. number, then continuous
				IF (@FootStampGuid <> 0)
				BEGIN

					--CUSTOMISE DATE TIME FORMAT RISPL
					SET @FaxDateTime_Formatted = (REPLACE(CONVERT(VARCHAR(11), @FaxDateTime, 6), ' ', '-') + ' ' + CONVERT(VARCHAR(5), @FaxDateTime, 114))
					
					IF (@csn = '-1')
					BEGIN
						SET @SyncFieldForLoopback = (SELECT SyncFieldForLoopback FROM CS_FootStamp WITH (NOLOCK) WHERE FootStampGuid = @FootStampGuid)
						set @ValueForLoopback = ''
						SET @SenderEmail= ''

						IF (@SyncFieldForLoopback is not null and @SyncFieldForLoopback <> '')
						BEGIN
							SELECT top 1 @SubjectLine = Subject ,@ValueForLoopback = CustomCode2,@SenderEmail= BillingCode, @FaxguidNeedUpdate = FaxGuid FROM FM_FAX WITH (NOLOCK) WHERE RemoteFaxNumber = @UpdatedCalledNo 
								and ISReceived = 0 and (CustomCode2 is not null and CustomCode2 <> '') and (BillingCode is not null and BillingCode <> '')and Status = 4 order by FaxGuid

							IF (@ValueForLoopback is null)
							BEGIN
									set @ValueForLoopback = ''
									set @SenderEmail = ''
									set @SubjectLine = ''
							END
							ELSE
							BEGIN
								set @ValueForLoopback = (REPLACE(CONVERT(VARCHAR(11), CAST(@ValueForLoopback as datetime), 6), ' ', '-') + ' ' + CONVERT(VARCHAR(5), CAST(@ValueForLoopback as datetime), 114))
								set @SenderEmail= @SenderEmail
							END																
						END
					END
					ELSE
						BEGIN
							SET @ValueForLoopback = '';					
					END
								
					
						

					-- if DID is NULL then continuous, because DID field will be temp save the CountNumber for update to CustomCode if receive Fax Success
					IF ((SELECT DID from FM_FaxIn WITH (NOLOCK) WHERE FaxInGuid = @UpdatedFaxInGuid) is null)
						-- if PageCount > 0, then continuous, this to avoid an unsuccess receive fax with no page to get the CoutNumber
						--IF ((SELECT PageCount from FM_FaxIn WITH (NOLOCK) WHERE FaxInGuid = @UpdatedFaxInGuid) > 0)				
						IF ((@UpdatedResultCode = '100' or @UpdatedResultCode is not NULL) and @UpdatedStatus <> 2 and @UpdatedPageCount > 0)
						BEGIN
								SET @Condition = (SELECT condition from CS_FootStamp WITH (NOLOCK) WHERE FootStampGuid = @FootStampGuid)				
								-- To get the Contition field setting
								SET @start = 1
								SET @end = CHARINDEX('|', @Condition)
								-- To get the first part of Contition (get X in "X|Y")
								SET @Condition1 = SUBSTRING(@Condition,@start,@end-1)
								-- To get the second part of Contition (get Y in "X|Y")
								SET @Condition2 = SUBSTRING(@Condition,@end + 1,LEN(@Condition)+1) 
								-- Get last CoutNumber
								SET @count = (SELECT CoutNumber FROM CS_FootStamp WITH (NOLOCK) WHERE FootStampGuid = @FootStampGuid) + 1
								-- Get Branch Code setting for this ext. number
								SET @brcode = (SELECT BranchCode FROM CS_FootStamp WITH (NOLOCK) WHERE FootStampGuid = @FootStampGuid)
								
							
								SET @DateFormat = (SELECT dayformat FROM CS_FootStamp WITH (NOLOCK) WHERE FootStampGuid = @FootStampGuid)

								

								-- If condition is "limit", then do the BEGIN until END									
								IF (@Condition1 = 'limit')
								BEGIN
									
									-- if last CountNumber is bigger then Condition2, then do the BEGIN until END
									IF (@count > @Condition2)
									BEGIN
										-- Reset the CountNumber to Start Number
										SET @count = (SELECT StartNumber FROM CS_FootStamp WITH (NOLOCK) WHERE FootStampGuid = @FootStampGuid)
									END
									
									Declare @CountPadding char(20), @CountChar varchar(10)
									
									Set @CountChar = rtrim(cast(@Count as varchar(6)))

									SET @CountPadding = rtrim(replicate('0',len(@Condition2) - len(@CountChar)))+@CountChar
									-- Update the CustomFootLineCode field for stamp customer footer to fax, and store the CountNumber to DID field for later to update CustomCode1
									--UPDATE FM_FaxIn WITH (ROWLOCK) SET CustomFootLineCode = (REPLACE(REPLACE((SELECT FooterString FROM CS_FootStamp WHERE FootStampGuid = @FootStampGuid),'{count}',@count),'{brcode}',@brcode)),DID = @count WHERE FaxInGuid = @UpdatedFaxInGuid	
									--RISPL REPLACE DATE

									IF (@csn = '-1')
									BEGIN
									UPDATE FM_FaxIn WITH (ROWLOCK) SET CustomFootLineCode = (REPLACE(REPLACE(REPLACE(REPLACE(REPLACE((SELECT FooterString FROM CS_FootStamp WHERE FootStampGuid = @FootStampGuid),'{count}',rtrim(@CountPadding)),'{brcode}',@brcode),'{date}','')
									,'{fieldforloopback}',@ValueForLoopback),'01JAN1900 00:00',@FaxDateTime_Formatted)), DID = @count WHERE FaxInGuid = @UpdatedFaxInGuid
									END
									ELSE
									BEGIN
									UPDATE FM_FaxIn WITH (ROWLOCK) SET CustomFootLineCode = (REPLACE(REPLACE(REPLACE(REPLACE((SELECT FooterString FROM CS_FootStamp WHERE FootStampGuid = @FootStampGuid),'{count}',rtrim(@CountPadding)),'{brcode}',@brcode),'{date}',@FaxDateTime_Formatted)
									,'{fieldforloopback}','')), DID = @count WHERE FaxInGuid = @UpdatedFaxInGuid
									END

									-- Update the Last CoutNumber for next fax
									UPDATE CS_FootStamp  WITH (ROWLOCK)SET CoutNumber = @count WHERE FootStampGuid = @FootStampGuid
								END
								
								-- If condition is "daily", then do the BEGIN until END									
								IF (@Condition1 = 'daily')
								BEGIN
									-- get the next reset time from NextResetDate Field
									SET @nextresettime = REPLACE(CONVERT(VARCHAR(5),(SELECT NextResetDate FROM CS_FootStamp WHERE FootStampGuid = @FootStampGuid),108),':','')
									-- get the next reset date from NextResetDate Field
									SET @nextresetdate = REPLACE(REPLACE(CONVERT(VARCHAR(10),(SELECT NextResetDate FROM CS_FootStamp WHERE FootStampGuid = @FootStampGuid),111),'-',''),'/','')									
									
									-- Convert NOW time to HHMMSS and convert NOW date to YYYYMMDD, then compare with next reset time and nexet reset date, if true then do BEGIN until END
									IF ((@nextresettime <= REPLACE(CONVERT(VARCHAR(5),GETDATE(),108),':','')) AND (@NextResetDate <= REPLACE(REPLACE(CONVERT(VARCHAR(10),GETDATE(),111),'-',''),'/','')))
									BEGIN
										-- Reset the CountNumber to Start Number
										SET @count = (SELECT StartNumber FROM CS_FootStamp WITH (NOLOCK) WHERE FootStampGuid = @FootStampGuid)
										-- If NextResetTime is HHM format, then convert it back to HHMM
										IF (LEN(@NextResetTime) = 3)
										BEGIN
											SET @NextResetTime = STUFF(@NextResetTime,1,0,'0')
										END
										
										-- After reset the CountNumber, then update the next reset day by add one day																		
										UPDATE CS_FootStamp set nextresetdate = DATEADD(Day,1,STUFF(STUFF(STUFF(STUFF(@NextResetDate + @NextResetTime,5,0,'-'),8,0,'-'),11,0,' '),14,0,':')) WHERE FootStampGuid
										= @FootStampGuid
									END
									
									-- Update the CustomFootLineCode field for stamp customer footer to fax, and store the CountNumber to DID field for later to update CustomCode1
									UPDATE FM_FaxIn WITH (ROWLOCK) SET CustomFootLineCode = (REPLACE(REPLACE((SELECT FooterString FROM CS_FootStamp WHERE FootStampGuid = @FootStampGuid),'{count}',@count),'{brcode}',@brcode)),DID = @count WHERE FaxInGuid = @UpdatedFaxInGuid
									-- Update the Last CoutNumber for next fax
									UPDATE CS_FootStamp  WITH (ROWLOCK)SET CoutNumber = @count WHERE FootStampGuid = @FootStampGuid
								END
								IF (@Condition1 = 'year')
								BEGIN
									-- get the next reset time from NextResetDate Field
									SET @nextresettime = REPLACE(CONVERT(VARCHAR(5),(SELECT NextResetDate FROM CS_FootStamp WHERE FootStampGuid = @FootStampGuid),108),':','')
									-- get the next reset date from NextResetDate Field
									SET @nextresetdate = REPLACE(REPLACE(CONVERT(VARCHAR(10),(SELECT NextResetDate FROM CS_FootStamp WHERE FootStampGuid = @FootStampGuid),111),'-',''),'/','')									
									
									-- Convert NOW time to HHMMSS and convert NOW date to YYYYMMDD, then compare with next reset time and nexet reset date, if true then do BEGIN until END
									IF ((@nextresettime <= REPLACE(CONVERT(VARCHAR(5),GETDATE(),108),':','')) AND (@NextResetDate <= REPLACE(REPLACE(CONVERT(VARCHAR(10),GETDATE(),111),'-',''),'/','')))
									BEGIN
										-- Reset the CountNumber to Start Number
										SET @count = (SELECT StartNumber FROM CS_FootStamp WITH (NOLOCK) WHERE FootStampGuid = @FootStampGuid)
										-- If NextResetTime is HHM format, then convert it back to HHMM
										IF (LEN(@NextResetTime) = 3)
										BEGIN
											SET @NextResetTime = STUFF(@NextResetTime,1,0,'0')
										END								
										-- After reset the CountNumber, then update the next reset day by add one year																		
										UPDATE CS_FootStamp set nextresetdate = DATEADD(Year,1,STUFF(STUFF(STUFF(STUFF(@NextResetDate + @NextResetTime,5,0,'-'),8,0,'-'),11,0,' '),14,0,':')) WHERE FootStampGuid
										= @FootStampGuid
									END
									-- Update the CustomFootLineCode field for stamp customer footer to fax, and store the CountNumber to DID field for later to update CustomCode1
									UPDATE FM_FaxIn WITH (ROWLOCK) SET CustomFootLineCode = (REPLACE(REPLACE((SELECT FooterString FROM CS_FootStamp WHERE FootStampGuid = @FootStampGuid),'{count}',@count),'{brcode}',@brcode)),DID = @count WHERE FaxInGuid = @UpdatedFaxInGuid
									-- Update the Last CoutNumber for next fax
									UPDATE CS_FootStamp  WITH (ROWLOCK)SET CoutNumber = @count WHERE FootStampGuid = @FootStampGuid							
								END
						END
				END
				-- If have Foot Stamp setting for this ext. number and the status = 2 (mean receive complete)
				IF (@FootStampGuid <> 0 AND @UpdatedStatus = 2 AND @UpdatedPageCount > 0)
				BEGIN
				   -- Get the Branch Code from the Foot Stamp setting for this ext. number
					SET @brcode = (SELECT BranchCode FROM CS_FootStamp WITH (NOLOCK) WHERE FootStampGuid = @FootStampGuid)
					-- Update Custom Code 1 to the Fax Cout Number, Custom Code 2 to Date, Billing Code to Branch Code
					IF (@csn = '-1')
					BEGIN
						UPDATE FM_FAX WITH (ROWLOCK) SET CustomCode1 = (SELECT DID FROM FM_FaxIn WHERE FaxInGuid = @UpdatedFaxInGuid), 
						CustomCode2 = CONVERT(DATETIME,CreateTime,@DateFormat), BillingCode = @SenderEmail, Matter = REPLACE(@ValueForLoopback,'01JAN1900 00:00',@FaxDateTime_Formatted) WHERE FaxInGuid = @UpdatedFaxInGuid
						UPDATE FM_Fax SET ToName = @SubjectLine WHERE FaxInGuid = @UpdatedFaxInGuid 											
						IF (@FaxguidNeedUpdate is not null or @FaxguidNeedUpdate > 0)
									BEGIN
										UPDATE FM_FAX WITH (ROWLOCK) SET CustomCode2 = '' WHERE FAXGUID = @FaxguidNeedUpdate
									END	
						
					END
					ELSE
					BEGIN
						UPDATE FM_FAX WITH (ROWLOCK) SET CustomCode1 = (SELECT DID FROM FM_FaxIn WHERE FaxInGuid = @UpdatedFaxInGuid), CustomCode2 = CONVERT(DATETIME,CreateTime,@DateFormat), BillingCode = @SenderEmail, Matter = @FaxDateTime_Formatted WHERE FaxInGuid = @UpdatedFaxInGuid
						UPDATE FM_Fax SET ToName = @SubjectLine WHERE FaxInGuid = @UpdatedFaxInGuid													
					END
					-- Update DID field back to null, because we used the DID!!field to temp store the CountNumber for this fax



			Update FM_Fax WITH (ROWLOCK) SET Remark = replicate('0', 7 - len((SELECT DID FROM FM_FaxIn WHERE FaxInGuid = @UpdatedFaxInGuid))) + (SELECT DID FROM FM_FaxIn WHERE FaxInGuid = @UpdatedFaxInGuid) WHERE FaxInGuid = @UpdatedFaxInGuid
	
	Update FM_Fax WITH (ROWLOCK) SET CustomCode1 = replicate('0', 7 - len((SELECT DID FROM FM_FaxIn WHERE FaxInGuid = @UpdatedFaxInGuid))) + (SELECT DID FROM FM_FaxIn WHERE FaxInGuid = @UpdatedFaxInGuid) WHERE FaxInGuid = @UpdatedFaxInGuid		

							UPDATE FM_FaxIn with (ROWLOCK) set DID = null where FaxInGuid = @UpdatedFaxInGuid							
				END
			END		
			
			--@FAXDATETIME RISPL	
			FETCH NEXT FROM ObsSet_Cursor_FM_FaxIn INTO @UpdatedFaxInGuid, @UpdatedCalledNo, @UpdatedStatus, @UpdatedResultCode, @UpdatedPageCount, @FaxDateTime, @csn
		END
		CLOSE ObsSet_Cursor_FM_FaxIn
		DEALLOCATE ObsSet_Cursor_FM_FaxIn
END


