/** 2009-01-11 **/
set names 'cp1251';
set @zSKIN_ID = (select id from SKINS where code='mafia_ru');

--
-- myautoid (level=1)
--
set @zCMDNAME = 'myautoid';
set @zCMDID = (select id from COMMANDS where name = @zCMDNAME);
delete from ACCESS_RIGHTS where command_id = @zCMDID;
delete from COMMANDS_ALIASES where cmd_id = @zCMDID;
delete from COMMANDS where id = @zCMDID;

insert into COMMANDS(name,cmdGroup,source) values(@zCMDNAME,'U','m');
set @zCMDID = (select id from COMMANDS where name = @zCMDNAME);
insert into COMMANDS_ALIASES(name,cmd_id,skin_id) values('��������',@zCMDID,@zSKIN_ID);

-- ����� (user)
set @zGID=(select id from USER_GROUPS where code='user');
insert into ACCESS_RIGHTS(command_id,owner_type,owner_id,may_execute,may_assign) values(@zCMDID,0,@zGID,1,0);



/** 2009-01-11 **/
set names 'cp1251';
set @zSKIN_ID = (select id from SKINS where code='mafia_ru');

set @zMSGNAME = 'authorize_yourself_at_nickserv_before_turning_autoid_on';
set @zMSGTEXT = '������������� � $NICK ������, ��� �������� ����-������������� � ����.';
delete from MESSAGES where name = @zMSGNAME and skin_id = @zSKIN_ID;
insert into MESSAGES(name,value,skin_id,ovr,user_id) values(@zMSGNAME,@zMSGTEXT,@zSKIN_ID,0,0);



/** 2009-01-11 **/
set names 'cp1251';
set @zSKIN_ID = (select id from SKINS where code='mafia_ru');

--
-- nickserv_notice_service (level=5)
--
set @SNAME = 'nickserv_notice_service';
delete from SETTINGS_RIGHTS where setting_name = @SNAME;
delete from SETTINGS_DESCRIPTIONS where setting_name = @SNAME;
delete from SETTINGS where name = @SNAME;

insert into SETTINGS(name,value,ovr,user_id) values(@SNAME,'',0,0);
insert into SETTINGS_DESCRIPTIONS(setting_name,description,skin_id,ovr,user_id) values(@SNAME,'������ ����� (���!�����@����), � �������� �������� ����������� �� ������������� �� ��� � �������� (+r, -r)',@zSKIN_ID,0,0);

-- ������������� (admin)
set @zGID=(select id from USER_GROUPS where code='admin');
insert into SETTINGS_RIGHTS(setting_name,owner_type,owner_id,may_write) values(@SNAME,0,@zGID,1);


--
-- auto_authorize_registered_nicks (level=4)
--
set @SNAME = 'auto_authorize_registered_nicks';
delete from SETTINGS_RIGHTS where setting_name = @SNAME;
delete from SETTINGS_DESCRIPTIONS where setting_name = @SNAME;
delete from SETTINGS where name = @SNAME;

insert into SETTINGS(name,value,ovr,user_id) values(@SNAME,'no',0,0);
insert into SETTINGS_DESCRIPTIONS(setting_name,description,skin_id,ovr,user_id) values(@SNAME,'������������� ���������������� � ���� ������, �������������������� �� ��� � ��������',@zSKIN_ID,0,0);

-- �������� (op)
set @zGID=(select id from USER_GROUPS where code='op');
insert into SETTINGS_RIGHTS(setting_name,owner_type,owner_id,may_write) values(@SNAME,0,@zGID,1);




/** 2009-01-13 **/
set names 'cp1251';
set @zSKIN_ID = (select id from SKINS where code='mafia_ru');

--
-- commandhistory (level=3)
--
set @zCMDNAME = 'commandhistory';
set @zCMDID = (select id from COMMANDS where name = @zCMDNAME);
delete from ACCESS_RIGHTS where command_id = @zCMDID;
delete from COMMANDS_ALIASES where cmd_id = @zCMDID;
delete from COMMANDS where id = @zCMDID;

insert into COMMANDS(name,cmdGroup,source) values(@zCMDNAME,'A','m');
set @zCMDID = (select id from COMMANDS where name = @zCMDNAME);

-- ������������� ���� (gm)
set @zGID=(select id from USER_GROUPS where code='gm');
insert into ACCESS_RIGHTS(command_id,owner_type,owner_id,may_execute,may_assign) values(@zCMDID,0,@zGID,1,0);



/** 2009-01-13 **/
set names 'cp1251';
set @zSKIN_ID = (select id from SKINS where code='mafia_ru');

set @zMSGNAME = 'command_history_is_empty';
set @zMSGTEXT = '�����.';
delete from MESSAGES where name = @zMSGNAME and skin_id = @zSKIN_ID;
insert into MESSAGES(name,value,skin_id,ovr,user_id) values(@zMSGNAME,@zMSGTEXT,@zSKIN_ID,0,0);

set @zMSGNAME = 'no_such_command_history_entry_id';
set @zMSGTEXT = '��� ������ � ����� �������!';
delete from MESSAGES where name = @zMSGNAME and skin_id = @zSKIN_ID;
insert into MESSAGES(name,value,skin_id,ovr,user_id) values(@zMSGNAME,@zMSGTEXT,@zSKIN_ID,0,0);

set @zMSGNAME = 'user_used_raw_command_notice';
set @zMSGTEXT = '$NICK ����������� ������� <n>!raw</n> (id=$NUMBER).';
delete from MESSAGES where name = @zMSGNAME and skin_id = @zSKIN_ID;
insert into MESSAGES(name,value,skin_id,ovr,user_id) values(@zMSGNAME,@zMSGTEXT,@zSKIN_ID,0,0);

set @zMSGNAME = 'you_must_specify_artifact_price';
set @zMSGTEXT = '�� ������ ������� ���� ���������, ������� �� ������ ��������� �� ����!';
delete from MESSAGES where name = @zMSGNAME and skin_id = @zSKIN_ID;
insert into MESSAGES(name,value,skin_id,ovr,user_id) values(@zMSGNAME,@zMSGTEXT,@zSKIN_ID,0,0);



/** 2009-01-13 **/
set names 'cp1251';
set @zSKIN_ID = (select id from SKINS where code='mafia_ru');
--
-- notify_admins_on_raw_usage (level=5)
--
set @SNAME = 'notify_admins_on_raw_usage';
delete from SETTINGS_RIGHTS where setting_name = @SNAME;
delete from SETTINGS_DESCRIPTIONS where setting_name = @SNAME;
delete from SETTINGS where name = @SNAME;

insert into SETTINGS(name,value,ovr,user_id) values(@SNAME,'yes',0,0);
insert into SETTINGS_DESCRIPTIONS(setting_name,description,skin_id,ovr,user_id) values(@SNAME,'���������� �� ������� � ����� ������������� ������� !raw',@zSKIN_ID,0,0);

-- ������������� (admin)
set @zGID=(select id from USER_GROUPS where code='admin');
insert into SETTINGS_RIGHTS(setting_name,owner_type,owner_id,may_write) values(@SNAME,0,@zGID,1);


--
-- max_command_history_lines (level=5)
--
set @SNAME = 'max_command_history_lines';
delete from SETTINGS_RIGHTS where setting_name = @SNAME;
delete from SETTINGS_DESCRIPTIONS where setting_name = @SNAME;
delete from SETTINGS where name = @SNAME;

insert into SETTINGS(name,value,ovr,user_id) values(@SNAME,'20',0,0);
insert into SETTINGS_DESCRIPTIONS(setting_name,description,skin_id,ovr,user_id) values(@SNAME,'������������ ���������� �������, ��������� �������� !commandhistory',@zSKIN_ID,0,0);

-- ������������� (admin)
set @zGID=(select id from USER_GROUPS where code='admin');
insert into SETTINGS_RIGHTS(setting_name,owner_type,owner_id,may_write) values(@SNAME,0,@zGID,1);


--
-- enable_min_artifact_price_restriction (level=3)
--
set @SNAME = 'enable_min_artifact_price_restriction';
delete from SETTINGS_RIGHTS where setting_name = @SNAME;
delete from SETTINGS_DESCRIPTIONS where setting_name = @SNAME;
delete from SETTINGS where name = @SNAME;

insert into SETTINGS(name,value,ovr,user_id) values(@SNAME,'yes',0,0);
insert into SETTINGS_DESCRIPTIONS(setting_name,description,skin_id,ovr,user_id) values(@SNAME,'������ ����� ��������� ��������� ������� �� ����������� ����',@zSKIN_ID,0,0);

-- ������������� ���� (gm)
set @zGID=(select id from USER_GROUPS where code='gm');
insert into SETTINGS_RIGHTS(setting_name,owner_type,owner_id,may_write) values(@SNAME,0,@zGID,1);


-- ����������� ��� !mypassword - ��������� ������� (������)
-- ����������� � ������� ������ � �������� ����.
update COMMANDS_HISTORY set params = 'N/A' where command = 'mypassword';
