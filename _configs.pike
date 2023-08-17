
// ### Тут описываются всякие процедуры чтения файлов конфигурации. Сюда лучше не заглядывать.

/**
 * Тип строки в таблице с топиками и баннерами.
 */
enum ChannelStringType {
	CHS_TOPIC,   // топик
	CHS_BANNER   // баннер
}

int loadConfiguration() {
	settings = ([ ]);
	int rc = 1
		&& loadConfigurationFile("mafion.cfg")
		&& loadConfigurationFile("mafion.ovr")
		;
	if (rc && !exportMode) {
		loadSkins();
		rc &= loadConfigurationDB();
	}
	return rc;
} // int loadConfiguration()

int loadConfigurationFile(string filename) {
	write(sprintf("Reading configuration file '%s'... ",filename));

	Stdio.File file = Stdio.File();
	if (!file->open(filename, "r")) {
		write(sprintf("Error reading [%s]!\n",filename));
		exit(0);
	}

	array text = file->read() / "\n";
	write(sprintf("- %d line(s) read\n",sizeof(text)));


	int lineNo = 0;
	foreach (text, string s) {
		lineNo++;
		if (s!="" && search(s,"=")>=0 && s[0]!='#') {
			string originalKey = String.trim_whites((s/"=")[0]);
			string key = lower(originalKey);//String.trim_whites((s/"=")[0]));
			string param = String.trim_whites((s/"=")[1]);

			if (sizeof(getparams(param,";"))<3) {
				write("Wrong key definition in file %s line %d (to few parameters!)\n",filename,lineNo);
				exit(0);
			}

			mixed value = String.trim_whites(getparams(param,";")[0]);
			int level = (int)String.trim_whites(getparams(param,";")[1]);
			string name = String.trim_whites(getparams(param,";")[2]);

			settings[key] = Settings();
			settings[key]->value = value;
			settings[key]->level = level;
			settings[key]->name = name;
			settings[key]->originalKey = originalKey;
		}
	}
	return 1;
}


/**
 * Загружает из базы данные о существующих скинах.
 */
void loadSkins() {
	constant THIS_NAME = "loadSkins";
	write("Reading skins table... ");

	skins = ([ ]);

	Sql.Sql db = game->sqlConnect();
	sql_result_t res;
	sql_row_t row;
	string query;

	query = "select id, code, name from SKINS";
	res = db->big_query(query);
	while ( 0 != (row = res->fetch_row()) ) {
		int fidx = 0;
		int id = (int)row[fidx++];
		string code = row[fidx++];
		string name = row[fidx++];
		BotSkin bs = BotSkin(id, code, name);
		skins[code] = bs;
	}

	write("- %d skin(s) loaded.\n", sizeof(skins));
} // void loadSkinsDB()

/**
 * Загружает настройки бота (mafion.cfg) из базы.
 */
int loadConfigurationDB() {
	constant THIS_NAME = "loadConfigurationDB";
	write("Reading configuration table... ");

	Sql.Sql db = game->sqlConnect();
	sql_result_t res;
	sql_row_t row;
	string query;
	int keys_read = 0, new_keys = 0;

	query = "select distinct(name) from SETTINGS";
	res = db->big_query(query);
	while ( 0 != (row = res->fetch_row()) ) {
		string key = lower(row[0]);
		keys_read++;
		if (zero_type(settings[key])) {
			new_keys++;
		}
		loadSettingDB(key);
	}
	write("- %d key(s) read, %d not in file.\n", keys_read, new_keys);
} // int loadConfigurationDB()


/**
 * Загружает настройку бота из базы.
 * @param key - ключ (код) настройки.
 * @param skinCode - код скина. Если не указан, то будет взят дефолтный.
 */
void loadSettingDB(string key, void|string skinCode) {
	Sql.Sql db = game->sqlConnect();
	sql_result_t res;
	sql_row_t row;
	string query;

	query = sprintf("select id, name, value, ovr from SETTINGS where name = '%s' order by ovr desc limit 1",
		db->quote(key));
	row = db->big_query(query)->fetch_row();
	int fidx = 0;
	int id = (int)row[fidx++];
	string originalKey = row[fidx++];
	string value = row[fidx++];
	boolean isOvr = 0 != (int)row[fidx++];
	key = lower(originalKey);
	Settings s = settings[key];
	if (zero_type(s)) {
		s = settings[key] = Settings();
	}
	s->id = id;
	s->originalKey = originalKey;
	s->value = value;
	s->isOvr = isOvr;
//write("%s: %s = %s\n", THIS_NAME, originalKey, value);

	// Загрузить описание (краткий хелп) настройки.
	loadSettingDescription(s, skinCode);

	// Загрузить разрешения.
	loadSettingsAccessRights(s, db);
} // void loadSettingDB()

/**
 * Загружает описание настройки бота.
 * @param s - настройка.
 * @param skinCode - код скина. Если не указан, то будет взят дефолтный.
 */
void loadSettingDescription(Settings s, void|string skinCode) {
	if (s->id < 1) { return; }

	BotSkin skin = zero_type(skinCode) ? getDefaultSkin() : skins[skinCode];

	Sql.Sql db = game->sqlConnect();
	string query = sprintf("select description from SETTINGS_DESCRIPTIONS where setting_name = '%s'"
		" and skin_id = %d order by ovr desc limit 1", db->quote(s->originalKey), skin->id);
	sql_row_t row = db->big_query(query)->fetch_row();
	if (row != 0) {
		s->name = row[0];
	}
} // void loadSettingDescription()
 

/**
 * Загружает из базы в кеш права доступа к настройке бота.
 * @param s - настройка.
 * @param conn - соединение с базой. Если не указано, будет открыто новое.
 * @return сколько прав загружено.
 */
int loadSettingsAccessRights(Settings s, void|Sql.Sql conn) {
	s->clearAccessCache();
	Sql.Sql db = zero_type(conn) ? game->sqlConnect() : conn;
	string query = sprintf("select owner_type, owner_id, may_write, may_assign from SETTINGS_RIGHTS"
		" where setting_name = '%s'", db->quote(s->originalKey));
	sql_result_t res_acl = db->big_query(query);
	sql_row_t row_acl;
	int perms_read = 0;
	while ( 0 != (row_acl = res_acl->fetch_row()) ) {
		perms_read++;
		int fidx_acl = 0;
		int owner_type = (int)row_acl[fidx_acl++];
		int owner_id = (int)row_acl[fidx_acl++];
		int may_write = (int)row_acl[fidx_acl++];
		int may_assign = (int)row_acl[fidx_acl++];
/*
write("[%s]: row_acl=%O\n", s->originalKey, row_acl);
write("[%s]: owner_type=%s, owner_id=%d, may_write=%s, may_assign=%s\n", s->originalKey, 
	OWNER_GROUP == owner_type ? "OWNER_GROUP" : OWNER_USER == owner_type ? "OWNER_USER" : (string)owner_type,
	owner_id,
	ACL_WRITE_KEY == may_write ? "ACL_WRITE_KEY" : ACL_NO_WRITE_KEY == may_write ? "ACL_NO_WRITE_KEY" : (string)may_write,
	ACL_ASSIGN == may_assign ? "ACL_ASSIGN" : ACL_NO_ASSIGN == may_assign ? "ACL_NO_ASSIGN" : (string)may_assign
	);
*/

		AccessType at = AT_INVALID;
		
		if (OWNER_GROUP != owner_type && OWNER_USER != owner_type) {
			logError(sprintf("PANIC: Unknown owner type for key '%s': %d",
				s->originalKey, owner_type));
			exit(1);
		}
		
		if (may_write != 0) {
//write("[%s]: may_write != 0 (%d), adding owner_id %d\n", s->originalKey, may_write, owner_id);
			switch (may_write) {
				case ACL_WRITE_KEY:		at = AT_ALLOW; break;
				case ACL_NO_WRITE_KEY:	at = AT_DENY; break;
				default:
					logError(sprintf("PANIC: Unknown may_write value"
						" for key '%s' (owner: type=%d, id=%d): %d",
						s->originalKey, owner_type, owner_id, may_write));
					exit(1);
			}
			s->putAccess(at, "ACL_WRITE_KEY", owner_type, owner_id);
		}
		
		if (may_assign != 0) {
//write("[%s]: may_assign != 0 (%d), adding owner_id %d\n", s->originalKey, may_assign, owner_id);
			switch (may_assign) {
				case ACL_ASSIGN:    at = AT_ALLOW; break;
				case ACL_NO_ASSIGN: at = AT_DENY; break;
				default:
					logError(sprintf("PANIC: Unknown may_assign value"
						" for key '%s' (owner: type=%d, id=%d): %d",
						s->originalKey, owner_type, owner_id, may_assign));
					exit(1);
			}
			s->putAccess(at, "ACL_ASSIGN", owner_type, owner_id);
		}
	} // while ( 0 != (row_acl = res_acl->fetch_row()) )
/*
write("[%s (id=%d)]: %d access right(s) read: allowed groups=[write=%d, read=%d], "
	"denied groups=[write=%d, read=%d], allowed users=[write=%d, read=%d], "
	"denied users=[write=%d, assign=%d]\n", s->originalKey, s->id, perms_read,
	sizeof(s->allowed_groups["ACL_WRITE_KEY"]), sizeof(s->allowed_groups["ACL_READ_KEY"]),
	sizeof(s->denied_groups["ACL_WRITE_KEY"]), sizeof(s->denied_groups["ACL_READ_KEY"]),
	sizeof(s->allowed_users["ACL_WRITE_KEY"]), sizeof(s->allowed_users["ACL_READ_KEY"]),
	sizeof(s->denied_users["ACL_WRITE_KEY"]), sizeof(s->denied_users["ACL_READ_KEY"])
	);
*/
	return perms_read;
} // int loadSettingsAccessRights()



int loadLogin(string filename) {
	write(sprintf("Reading login file '%s'... ",filename));

	Stdio.File file    = Stdio.File();
	if (!file->open(filename, "r")) {
		write(sprintf("error!\n"));
		exit(0);
	}

	array text = file->read() / "\n";
	write(sprintf("- %d line(s) read\n",sizeof(text)));

	login_text = ({ });

	for (int i=0;i<sizeof(text);i++) {
		if (text[i]!="" && text[i][0]!='#') {
			login_text += ({ text[i]});
		}
	}
	return 1;
}

void clearCommands() {
	commands = ([ ]);
	commandsByGroups = ([ ]);
	commandGroups = ([ ]);
}

void clearCommandSources() {
	commandSources = ([ ]);
}

int loadCommands() {
	constant THIS_NAME = "loadCommands";
	clearCommands();
	clearCommandSources();
	if (exportMode) {
		return loadCommandsFile("commands.cfg");
	}
	loadCommandSources();
	loadCommandsDB();
	return 1;
}

/**
 * Загружает из базы источники команд.
 * @param skinCode - код скина. Если не указан, то будет взят дефолтный.
 * @return сколько источников загружено.
 */
int loadCommandSources(void|string skinCode) {
	constant THIS_NAME = "loadCommandSources";
	write("Reading command sources table... ");

	BotSkin skin = zero_type(skinCode) ? getDefaultSkin() : skins[skinCode];

	Sql.Sql db = game->sqlConnect();
	sql_result_t res;
	sql_row_t row;
	string query;

	int sources_loaded = 0;
	query = sprintf("select code, description from COMMANDS_SOURCES where skin_id = %d", skin->id);
	res = db->big_query(query);
	while( 0 != (row = res->fetch_row()) ) {
		string code = row[0], name = row[1];
		commandSources[code] = name;
		sources_loaded++;
	}
	write("- %d source(s) read.\n", sources_loaded);
	return sources_loaded;
} // int loadCommandSources()

/**
 * Загружает из базы команды бота.
 * @param skinCode - код скина. Если не указан, то будет взят дефолтный.
 * @return хз.
 */
int loadCommandsDB(void|string skinCode) {
   constant THIS_NAME = "loadCommands";
   write("Reading commands table... ");

	BotSkin skin = zero_type(skinCode) ? getDefaultSkin() : skins[skinCode];

   Sql.Sql db = game->sqlConnect();
   sql_result_t res;
   sql_row_t row;
   string query;

   int commands_loaded = 0;
   // Загрузить группы команд.
   string SHOP_CG = settings["shopcommandgroup"]->value;
   query = sprintf("select code, description from COMMANDS_GROUPS where skin_id = %d", skin->id);
   res = db->big_query(query);
   while ((row = res->fetch_row()) != 0) {
      string code = row[0];
      string desc = row[1];
      commandGroups[code] = desc;
      // Загрузить команды.
      // Пропустить группу команд применения артефактов.
      if (code != SHOP_CG) {
         commands_loaded += loadCommandsByGroup(code, skinCode);
      }
   }
   if (sizeof(commandGroups) < 1) {
      log(debug_log, "\nPANIC: no command groups found.");
      exit(1);
   }

   write("- %d command(s) in %d group(s) read.\n", commands_loaded, sizeof(commandGroups));

//write("%s: END: sizeof(commands)=%d\n", THIS_NAME, sizeof(commands));
   return 1;
} // int loadCommandsDB()

/**
 * Загружает команды определённой группы.
 * @param code - код группы команд (!A, !G и т.п.).
 * @param skinCode - код скина. Если не указан, то будет взят дефолтный.
 * @return количество загруженных команд.
 * @throws если группа с кодом code не существует в commandGroups
 * или существует более одной команды с одинаковым именем.
 */
int loadCommandsByGroup(string code, void|string skinCode) {
//   commandsByGroups[code] = ({ });

	BotSkin skin = zero_type(skinCode) ? getDefaultSkin() : skins[skinCode];

	Sql.Sql db = game->sqlConnect();
	sql_result_t res;
	sql_row_t row;
	string query;

	int commands_loaded = 0;

	query = sprintf("select id, name, source from COMMANDS where cmdGroup = '%s'", db->quote(code));
	res = db->big_query(query);
	while ((row = res->fetch_row()) != 0) {
		int fidx = 0;
		int id = (int)row[fidx++];
		string name = row[fidx++];
		string source = row[fidx++];
//write("%s: command: id=%d, name='%s', group='%s', source='%s'\n", THIS_NAME, id, name, code, source);
		if (zero_type(commandGroups[code])) {
			error("PANIC: command '%s': unknown group: %s", name, code || "(null)"); // throw
			exit(1);
		}
		if (!zero_type(commands[name])) {
			error("PANIC: command '%s' already exists.", name); // throw
			exit(1);
		}
		Commands cmd = Commands();
		cmd->id = id;
		cmd->name = name;
		cmd->group = code;
		cmd->source = source;

		// Загрузить синонимы команды.
		loadCommandAliases(cmd, skinCode);

		commands[name] = cmd;
		commands_loaded++;
		commandsByGroups[code] += ({ name });

		// Загрузить в кеш разрешения на команду.
		loadCommandAccessRights(cmd, db);
	}
	return commands_loaded;
} // int loadCommandsByGroup()

/**
 * Загружает синонимы команды бота.
 * @param cmd - команда бота.
 * @param skinCode - код скина. Если не указан, то будет взят дефолтный.
 */
void loadCommandAliases(Commands cmd, void|string skinCode) {
	BotSkin skin = zero_type(skinCode) ? getDefaultSkin() : skins[skinCode];

	Sql.Sql db = game->sqlConnect();
	string query = sprintf("select name from COMMANDS_ALIASES where cmd_id = %d and skin_id = %d", cmd->id, skin->id);
	sql_result_t res = db->big_query(query);
	sql_row_t row = res->fetch_row();
	if (row != 0) {
		cmd->synonimes = ({ });
		do {
			cmd->synonimes += ({ row[0] });
		} while( 0 != (row = res->fetch_row()) );
	}
} // void loadCommandAliases()

/**
 * Загружает из базы в кеш права доступа к команде.
 * @param cmd - команда.
 * @param conn - соединение с базой. Если не указано, будет открыто новое.
 * @return сколько прав загружено.
 */
int loadCommandAccessRights(Commands cmd, void|Sql.Sql conn) {
	cmd->clearAccessCache();
	int perms_read = 0;
	Sql.Sql db = zero_type(conn) ? game->sqlConnect() : conn;
	string query = sprintf("select owner_type, owner_id, may_execute, may_assign from ACCESS_RIGHTS"
		" where command_id = %d", cmd->id);
	sql_result_t res_acl = db->big_query(query);
	sql_row_t row_acl;
	while ( 0 != (row_acl = res_acl->fetch_row()) ) {
		perms_read++;
		int fidx_acl = 0;
		int owner_type = (int)row_acl[fidx_acl++];
		int owner_id = (int)row_acl[fidx_acl++];
		int may_execute = (int)row_acl[fidx_acl++];
		int may_assign = (int)row_acl[fidx_acl++];
/*
write("[%s]: row_acl=%O\n", cmd->name, row_acl);
write("[%s]: owner_type=%s, owner_id=%d, may_execute=%s, may_assign=%s\n", cmd->name, 
	OWNER_GROUP == owner_type ? "OWNER_GROUP" : OWNER_USER == owner_type ? "OWNER_USER" : (string)owner_type,
	owner_id,
	ACL_EXECUTE == may_execute ? "ACL_EXECUTE" : ACL_NO_EXECUTE == may_execute ? "ACL_NO_EXECUTE" : (string)may_execute,
	ACL_ASSIGN == may_assign ? "ACL_ASSIGN" : ACL_NO_ASSIGN == may_assign ? "ACL_NO_ASSIGN" : (string)may_assign
	);
*/

		AccessType at = AT_INVALID;
		
		if (OWNER_GROUP != owner_type && OWNER_USER != owner_type) {
			logError(sprintf("PANIC: Unknown owner type for command '%s': %d",
				cmd->name, owner_type));
			exit(1);
		}
		
		if (may_execute != 0) {
//write("[%s]: may_execute != 0 (%d), adding owner_id %d\n", cmd->name, may_execute, owner_id);
			switch (may_execute) {
				case ACL_EXECUTE:    at = AT_ALLOW; break;
				case ACL_NO_EXECUTE: at = AT_DENY; break;
				default:
					log(debug_log, sprintf("\nPANIC: Unknown may_execute value"
						" for command '%s' (owner: type=%d, id=%d): %d", 
						cmd->name, owner_type, owner_id, may_execute));
					exit(1);
			}
			cmd->putAccess(at, "ACL_EXECUTE", owner_type, owner_id);
		}
		
		if (may_assign != 0) {
//write("[%s]: may_assign != 0 (%d), adding owner_id %d\n", cmd->name, may_assign, owner_id);
			switch (may_assign) {
				case ACL_ASSIGN:     at = AT_ALLOW; break;
				case ACL_NO_ASSIGN:  at = AT_DENY; break;
				default:
					logError(sprintf("PANIC: Unknown may_assign value"
						" for command '%s' (owner: type=%d, id=%d): %d", 
						cmd->name, owner_type, owner_id, may_assign));
					exit(1);
			}
			cmd->putAccess(at, "ACL_ASSIGN", owner_type, owner_id);
		}		
	} // while ( 0 != (row_acl = res_acl->fetch_row()) )
/*
write("[%s (id=%d)]: %d access right(s) read: allowed groups=[execute=%d, assign=%d], "
	"denied groups=[execute=%d, assign=%d], allowed users=[execute=%d, assign=%d], "
	"denied users=[execute=%d, assign=%d]\n", cmd->name, cmd->id, perms_read,
	sizeof(cmd->allowed_groups["ACL_EXECUTE"]),	sizeof(cmd->allowed_groups["ACL_ASSIGN"]),
	sizeof(cmd->denied_groups["ACL_EXECUTE"]), sizeof(cmd->denied_groups["ACL_ASSIGN"]),
	sizeof(cmd->allowed_users["ACL_EXECUTE"]), sizeof(cmd->allowed_users["ACL_ASSIGN"]),
	sizeof(cmd->denied_users["ACL_EXECUTE"]), sizeof(cmd->denied_users["ACL_ASSIGN"])
	);
*/
	return perms_read;
} // int loadCommandAccessRights();

int loadCommandsFile(string filename) {
   write(sprintf("Reading commands file '%s'... ",filename));
   Stdio.File file = Stdio.File();
   if (!file->open(filename, "r")) {
      write(sprintf("error!\n"));
      exit(0);
   }

   array text = file->read() / "\n";
   write("- %d line(s) read\n", sizeof(text));
   string group = "";

   foreach (text, string s) {
      if (s != "" && search(s, "=") >= 0 && s[0] != '#') {
         if (s[0] == '!' && sizeof(s) > 1) {
            group = s[1..1];
            commandGroups[group] = sizeof(s / "=") > 1 ? (s / "=")[1] : "unknown";
         } else {
            array(string) keywords = map(s / "=", String.trim_whites);
            keywords[0] = lower_case(keywords[0]);
            string key = keywords[0];
            string param = replace(keywords[1], "	", "");
            array(string) keys = map(map(param / ",", String.trim_whites), lower_case);
            commands[key] = Commands();
            commands[key]->level = (int)keys[0];
            commands[key]->source = keys[1];
            commands[key]->group = group;
            commands[key]->name = keys[2];
            for (int i1 = 3; i1 < sizeof(keys); i1++) commands[key]->synonimes += ({ keys[i1] });
         }
      }

   }

   return 1;
}

int loadLevels() {
	userlevelName = ([ ]);
   if (exportMode) {
      return loadLevelsFile("levels.cfg");
   }
   return 1;
}

int loadLevelsFile(string filename) {
   write(sprintf("Reading levels file '%s'... ",filename));
   userlevelName = ([ ]);

   Stdio.File file    = Stdio.File();
   if (!file->open(filename, "r")) {
      write(sprintf("error!\n"));
      exit(0);
   }

   array text = file->read() / "\n";
   write(sprintf("- %d line(s) read\n",sizeof(text)));
   array keys;

   foreach (text, string line) {
      if (line!="" && search(line,",")>=0 && line[0]!='#') {
         keys         = line/",";
         keys[0]        = String.trim_whites(keys[0]);
         keys[1]        = String.trim_whites(keys[1]);
         keys[2]        = String.trim_whites(keys[2]);
         userlevelName[(int)keys[0]]    = UserlevelName();
         userlevelName[(int)keys[0]]->name  = keys[1];
         userlevelName[(int)keys[0]]->subname = keys[2];
         userlevelName[(int)keys[0]]->multiples = keys[3];
      }
   }
   return 1;
}


int loadRoles() {
	roles = ([ ]);
	roleFeatures = ([ ]);
	int rc;
	if (exportMode) {
		rc = loadRolesFile("roles.cfg") && loadRolesFile("roles.ovr");
	} else {
		rc = 1;
		loadRolesDB();
	}
	return rc;
}

int loadRolesFile(string filename) {
   write(sprintf("Reading roles file '%s'... ",filename));

   Stdio.File file    = Stdio.File();
   if (!file->open(filename, "r")) {
      write(sprintf("error!\n"));
      exit(0);
   }

   array text = file->read() / "\n";
   write(sprintf("- %d line(s) read\n",sizeof(text)));
   array keys;
   string roleCode;

   foreach (text, string line) {
      if (line!="" && search(line,"=")>=0 && line[0]!='#') {
         string key = String.trim_whites(lower((line/"=")[0]));
         string value = String.trim_whites((line/"=")[1]);
//write("key=%s value=%s\n",key,value);
         switch (key) {
            case "role" :
               roleCode = value;
               if (!roles[roleCode])
                  switch (roleCode) {
                     case ROLE_MAFIOSI: roles[roleCode] = roleF(); break;
                     case ROLE_REPORTER: roles[roleCode] = roleR(); break;
                     case ROLE_ATTORNEY: roles[roleCode] = roleA(); break;
                     case ROLE_MANIAC: roles[roleCode] = roleM(); break;
                     case ROLE_KILLER: roles[roleCode] = roleK(); break;
                     case ROLE_CATTANI: roles[roleCode] = roleC(); break;
                     case ROLE_HOMELESS: roles[roleCode] = roleB(); break;
                     case ROLE_DOCTOR: roles[roleCode] = roleD(); break;
                     case ROLE_HACKER: roles[roleCode] = roleH(); break;
                     case ROLE_SLUT: roles[roleCode] = roleS(); break;
                     case ROLE_GUARDIAN: roles[roleCode] = roleG(); break;
                     case ROLE_TERRORIST: roles[roleCode] = roleT(); break;
                     case ROLE_CITIZEN: roles[roleCode] = roleZ(); break;
                     case ROLE_DEALER: roles[roleCode] = roleI(); break;
                     case ROLE_HOOLIGAN: roles[roleCode] = roleX(); break;
                     case ROLE_PUNK: roles[roleCode] = roleP(); break;
                     default:
                        throw( ({ sprintf("PANIC: unknown role code: %s\n", roleCode), backtrace() }) );
                  }
            break;

            case "name" :
               roles[roleCode]->name = String.trim_whites(value);
            break;
         
            case "repeatorder" :
               roles[roleCode]->maxRepeatOrder = (int)String.trim_whites(value);
            break;

            case "playersmin" :
               roles[roleCode]->playersMin = (int)String.trim_whites(value);
               if (roles[roleCode]->playersMin==0) { write(sprintf("ERROR: wrong playersMin for role %s!\n",roleCode)); exit(0); }
            break;

            case "voicelevel" :
               roles[roleCode]->voiceLevel = (int)String.trim_whites(value);
               if (roles[roleCode]->voiceLevel==0) { write(sprintf("ERROR: wrong voiceLevel for role %s!\n",roleCode)); exit(0); }
            break;

            case "levelsdivider" :
               for (int i=0;i<sizeof(getparams(value,","));i++) {
                  if ((int)String.trim_whites(getparams(value,",")[i])==0) { write(sprintf("ERROR: wrong levelsDivider for role %s!\n",roleCode)); exit(0); }
                  roles[roleCode]->levelDividers[i+2] = (int)String.trim_whites(getparams(value,",")[i]);
               }
            break;

            // формат: command = кодКоманды, уровень, требуетсяНик [, скрыватьДеньги ("hidePoints")] [, дополнительноКЗаказу (":extra")] , синоним1 [, ... синонимN]
            case "command" :
               Roles.Commands cmd = roles[roleCode]->Commands();
               array cmds = map(value / ",", String.trim_whites);
               cmd->code = cmds[0];
               cmd->level = (int)cmds[1];
               string nr = lower(cmds[2]);
               if (zero_type(nickRequirements[nr])) {
                  write("ERROR: command '%s': Invalid nick requirement: %s, expected '%s'", cmds[0], 
                     (nr || "(null)") > "" ? nr : "(empty string)", a_join(values(nickRequirementNames), "', or '"));
                  exit(1);
               }
               cmd->nickRequired = nickRequirements[nr];
               int start = 3;
               cmd->hidePoints = 0;
               if (lower(cmds[start]) == "hidepoints")
               {
                  cmd->hidePoints = true;
                  ++start;
               }
               if (lower(cmds[start]) == ":extra")
               {
                  cmd->isRegular = false;
                  ++start;
               }
               cmd->name = cmds[start];
               cmd->synonimes = ({ });
               for (int i = start + 1; i < sizeof(cmds); i++) {
                  cmd->synonimes += ({ cmds[i] });
               }
               roles[roleCode]->commands[cmd->code] = cmd;
            break;
         }
      }
   }
   return 1;
} // int loadRolesFile()

int loadRoleFile(string nick, string initRoleCode) {
   string filename = "roles.cfg";
//   write(sprintf("Reading roles file '%s'... ",filename));

   Stdio.File file    = Stdio.File();
   if (!file->open(filename, "r")) {
      write(sprintf("error!\n"));
      exit(0);
   }

   array text = file->read() / "\n";
   write(sprintf("- %d line(s) read\n",sizeof(text)));
   array keys;
   string roleCode = "";
   int  created = 0;

   foreach (text, string line) {
      if (line!="" && search(line,"=")>=0 && line[0]!='#') {
         string key = String.trim_whites(lower((line/"=")[0]));
         string value = String.trim_whites((line/"=")[1]);
         switch (key) {
            case "role" :
//write("roleCode=[%s] initRoleCode=[%s]\n",roleCode,initRoleCode);
               roleCode = value;
               if (initRoleCode!=roleCode) break;
               created = 1;
               if (!roles[roleCode])
                  switch (roleCode) {
                     case ROLE_MAFIOSI: roles[roleCode] = roleF(); break;
                     case ROLE_REPORTER: roles[roleCode] = roleR(); break;
                     case ROLE_ATTORNEY: roles[roleCode] = roleA(); break;
                     case ROLE_MANIAC: roles[roleCode] = roleM(); break;
                     case ROLE_KILLER: roles[roleCode] = roleK(); break;
                     case ROLE_CATTANI: roles[roleCode] = roleC(); break;
                     case ROLE_HOMELESS: roles[roleCode] = roleB(); break;
                     case ROLE_DOCTOR: roles[roleCode] = roleD(); break;
                     case ROLE_HACKER: roles[roleCode] = roleH(); break;
                     case ROLE_SLUT: roles[roleCode] = roleS(); break;
                     case ROLE_GUARDIAN: roles[roleCode] = roleG(); break;
                     case ROLE_TERRORIST: roles[roleCode] = roleT(); break;
                     case ROLE_CITIZEN: roles[roleCode] = roleZ(); break;
                     case ROLE_DEALER: roles[roleCode] = roleI(); break;
                     case ROLE_HOOLIGAN: roles[roleCode] = roleX(); break;
                     case ROLE_PUNK: roles[roleCode] = roleP(); break;
                     default:
                        throw( ({ sprintf("PANIC: unknown role code: %s\n", roleCode), backtrace() }) );
                  }
            break;

            case "name" :
               if (roleCode!=initRoleCode) break;
               roles[roleCode]->name = String.trim_whites(value);
            break;
         
            case "repeatorder" :
               if (roleCode!=initRoleCode) break;
               roles[roleCode]->maxRepeatOrder = (int)String.trim_whites(value);
            break;

            case "playersmin" :
               if (roleCode!=initRoleCode) break;
               roles[roleCode]->playersMin = (int)String.trim_whites(value);
               if (roles[roleCode]->playersMin==0) { write(sprintf("ERROR: wrong playersMin for role %s!\n",roleCode)); exit(0); }
            break;

            case "voicelevel" :
               if (roleCode!=initRoleCode) break;
               roles[roleCode]->voiceLevel = (int)String.trim_whites(value);
               if (roles[roleCode]->voiceLevel==0) { write(sprintf("ERROR: wrong voiceLevel for role %s!\n",roleCode)); exit(0); }
            break;

            case "levelsdivider" :
               if (roleCode!=initRoleCode) break;
               for (int i=0;i<sizeof(getparams(value,","));i++) {
                  if ((int)String.trim_whites(getparams(value,",")[i])==0) { write(sprintf("ERROR: wrong levelsDivider for role %s!\n",roleCode)); exit(0); }
                  roles[roleCode]->levelDividers[i+2] = (int)String.trim_whites(getparams(value,",")[i]);
               }
            break;

            case "command" :
               if (roleCode != initRoleCode) break;
               array cmds = map(value / ",", String.trim_whites);
               Roles.Commands cmd = roles[roleCode]->Commands();
               cmd->code = cmds[0];
               cmd->level = (int)cmds[1];
               string nr = lower(cmds[2]);
               if (zero_type(nickRequirements[nr])) {
                  irc->message(users[nick]->usernick, settings["color.error"]->value, sprintf("Invalid nick requirement: '%s'", nr));
                  return 0;
               }
               cmd->nickRequired = nickRequirements[nr];
               int start = 3;
               cmd->hidePoints = 0;
               if (lower(cmds[start]) == "hidepoints")
               {
                  cmd->hidePoints = true;
                  ++start;
               }
               if (lower(cmds[start]) == ":extra")
               {
                  cmd->isRegular = false;
                  ++start;
               }
               cmd->name = cmds[start];
               cmd->synonimes = ({ });
               for (int i = start + 1; i < sizeof(cmds); i++) {
                  cmd->synonimes += ({ cmds[i] });
               }
               roles[roleCode]->commands[cmd->code] = cmd;
            break;
         }
      }
   }
   if (created==1) {
      game->saveRoles();
      irc->message(settings["gamechannel"]->value,settings["color.regular"]->value,getMessage("role_was_reinited_by"),roles[initRoleCode]->name,users[nick]->title2,users[nick]->nick());
   } else {
      irc->notice(users[nick]->usernick, settings["color.error"]->value,
         getMessage("no_such_role"));
   }
   return 1;
} // int loadRoleFile()

int loadRolesDB() {
   constant THIS_NAME = "loadRolesDB";

	loadRolesFeatures();

   write("Reading roles table... ");
   Sql.Sql db = game->sqlConnect();
   sql_result_t res;
   sql_row_t row;
   string query;

   int commands_loaded = 0;

   query = "select distinct(role_id) from ROLES";
   res = db->big_query(query);
   while( 0 != (row = res->fetch_row()) ) {
		commands_loaded += loadRole(row[0], db);
   }

   write("- %d role(s) with %d command(s) read.\n", sizeof(roles), commands_loaded);

   return 1;
} // int loadRolesDB()


/**
 * Загружает описания фич ролей из базы.
 */
void loadRolesFeatures(void|string skinCode) {
	constant THIS_NAME = "loadRolesFeatures";

	BotSkin skin = zero_type(skinCode) ? getDefaultSkin() : skins[skinCode];

   write("Reading role features table... ");
   Sql.Sql db = game->sqlConnect();
   sql_result_t res;
   sql_row_t row;
   string query;

   int num_read = 0;
   query = sprintf("select code, description from ROLE_FEATURES where skin_id = %d", skin->id);
   res = db->big_query(query);
   while ( 0 != (row = res->fetch_row()) ) {
		num_read++;
		string code = row[0];
		string desc = row[1];
		roleFeatures[lower(code)] = desc;
   }

	write ("- %d feature(s) read.\n", num_read);
} // void loadRolesFeatures()

/**
 * Загружает параметры роли из базы.
 * @param code - код роли.
 * @param conn - соединение с базой. Если не указано, будет открыто новое.
 * @return сколько команд загружено.
 */
int loadRole(string code, void|Sql.Sql conn) {
	constant THIS_NAME = "loadRole";

	m_delete(roles, code);

	Roles r = 0;
	int commands_loaded = 0;

	Sql.Sql db = zero_type(conn) ? game->sqlConnect() : conn;
	sql_result_t res;
	sql_row_t row;
	string query;

	query = sprintf("select id, players_min, repeat_order, voice_level from ROLES"
		" where role_id = '%s' order by ovr desc limit 1", db->quote(code));
	res = db->big_query(query);
	row = res->fetch_row();
	if ( row != 0 ) {
		int fidx = 0;
		int roleID = (int)row[fidx++];
		int playersMin = (int)row[fidx++];
		int repeatOrder = (int)row[fidx++];
		int voiceLevel = (int)row[fidx++];

		switch (code) {
			case ROLE_ATTORNEY:     r = roleA(); break;
			case ROLE_HOMELESS:     r = roleB(); break;
			case ROLE_CATTANI:      r = roleC(); break;
			case ROLE_DOCTOR:       r = roleD(); break;
			case ROLE_MAFIOSI:      r = roleF(); break;
			case ROLE_GUARDIAN:     r = roleG(); break;
			case ROLE_HACKER:       r = roleH(); break;
			case ROLE_DEALER:       r = roleI(); break;
			case ROLE_KILLER:       r = roleK(); break;
			case ROLE_MANIAC:       r = roleM(); break;
			case ROLE_REPORTER:     r = roleR(); break;
			case ROLE_SLUT:         r = roleS(); break;
			case ROLE_TERRORIST:    r = roleT(); break;
			case ROLE_CITIZEN:      r = roleZ(); break;
			case ROLE_HOOLIGAN:     r = roleX(); break;
			case ROLE_PUNK:         r = roleP(); break;
			default:
				error("PANIC: Unknown role code: %s\n", code); // throw
		}
		r->id = roleID;
		r->code = code;
		r->playersMin = playersMin;
		r->maxRepeatOrder = repeatOrder;
		r->voiceLevel = voiceLevel;

		// Загрузить название роли.
		loadRoleName(r);

		// Загрузить делители уровней (levelsDivider).
		query = sprintf("select level, divider from ROLES_LEVELS where role_code = '%s' order by role_code, ovr", db->quote(code));
		sql_result_t res_ld = db->big_query(query);
		sql_row_t row_ld;
		while( 0 != (row_ld = res_ld->fetch_row()) ) {
			int fidx = 0;
			int ld_level = (int)row_ld[fidx++];
			int ld_divider = (int)row_ld[fidx++];
			r->levelDividers[ld_level] = ld_divider;
		}

		// Загрузить команды роли.
		commands_loaded += loadRoleCommands(r, db);

		// Загрузить фичи роли.
		loadRoleFeatures(r);

		roles[code] = r;
	} // if ( 0 != (row = res->fetch_row()) )

	return commands_loaded;
} // int loadRole()

/**
 * Загружает фичи роли.
 * @param r - роль.
 */
void loadRoleFeatures(Roles r) {
	constant THIS_NAME = "loadRoleFeatures";

	r->features = ([ ]);

   Sql.Sql db = game->sqlConnect();
   sql_result_t res;
   sql_row_t row;
   string query;

	query = sprintf("select feature_code, level from ROLES_FEATURES where role_code = '%s'"
		" order by feature_code, ovr", db->quote(r->code));
	res = db->big_query(query);
	while ( 0 != (row = res->fetch_row()) ) {
		string code = lower(row[0]);
		int level = (int)row[1];
		if (zero_type(roleFeatures[code])) {
			logError(sprintf("%s: role '%s': Unknown feature code: %s", THIS_NAME, r->code, row[0]));
			continue;
		}
		r->features[code] = level;
	}
} // void loadRoleFeatures()

/**
 * Загружает название роли.
 * @param r - роль.
 * @param skinCode - код скина. Если не указан, то будет взят дефолтный.
 */
void loadRoleName(Roles r, void|string skinCode) {
	BotSkin skin = zero_type(skinCode) ? getDefaultSkin() : skins[skinCode];
	
	Sql.Sql db = game->sqlConnect();
	string query = sprintf("select name from ROLES_NAMES where role_code = '%s' and skin_id = %d"
		" order by ovr desc limit 1", db->quote(r->code), skin->id);
	sql_row_t row = db->big_query(query)->fetch_row();
	if (row != 0) {
		r->name = row[0];
	}
} // void loadRoleName()

/**
 * Загружает команды роли из базы.
 * @param r - роль.
 * @param conn - соединение с базой. Если не указано, будет открыто новое.
 * @return сколько команд загружено.
 */
int loadRoleCommands(Roles r, void|Sql.Sql conn) {
	Sql.Sql db = zero_type(conn) ? game->sqlConnect() : conn;
	sql_result_t res;
	sql_row_t row;
	string query;

	int commands_loaded = 0;

	query = sprintf("select id, command_id, command_name, command_level, nick_required, hide_money, is_regular from ROLES_COMMANDS where role_code = '%s'", db->quote(r->code));
	res = db->big_query(query);
	while ( 0 != (row = res->fetch_row()) ) {
		int fidx_cmds = 0;
		int cmdID = (int)row[fidx_cmds++];
		string cmdName = row[fidx_cmds++];
		string cmdMainName = row[fidx_cmds++];
		int cmdLevel = (int)row[fidx_cmds++];
		NickRequirementType nrt = (int)row[fidx_cmds++];
		boolean hideMoney = 0 != (int)row[fidx_cmds++];
		boolean isRegular = 0 != (int)row[fidx_cmds++];
		Roles.Commands cmd = r->Commands();
		cmd->id = cmdID;
		cmd->code = cmdName;
		cmd->name = cmdMainName;
		cmd->level = cmdLevel;
		cmd->nickRequired = nrt;
		cmd->hidePoints = hideMoney;
		cmd->isRegular = isRegular;

		// Загрузить синонимы команды.
		loadRoleCommandAliases(r, cmd);

		r->commands[cmdName] = cmd;
		commands_loaded++;
	} // while ( 0 != (row = res->fetch_row()) )

	return commands_loaded;
} // int loadRoleCommands()

/**
 * Загружает синонимы команды роли.
 * @param r - роль.
 * @param cmdName - код команды, например killC.
 * @param skinCode - код скина. Если не указан, будет взят дефолтный.
 */
void loadRoleCommandAliases(Roles r, Roles.Commands cmd, void|string skinCode) {
	BotSkin skin = zero_type(skinCode) ? getDefaultSkin() : skins[skinCode];

	Sql.Sql db = game->sqlConnect();
	sql_result_t res;
	sql_row_t row;
	string query;
	
	query = sprintf("select alias from ROLES_COMMANDS_ALIASES where command_id = %d and skin_id = %d",
		cmd->id, skin->id);
	res = db->big_query(query);
	row = res->fetch_row();
	if (row != 0) {
		cmd->synonimes = ({ });
		do {
			cmd->synonimes += ({ row[0] });
		} while ( 0 != (row = res->fetch_row()) );
	}
} // void loadRoleCommandAliases()





int loadMessages() {
	messages = ([ ]);
   if (exportMode) {
      return loadMessagesFile("messages.txt");
   }
   return loadMessagesDB();
}

int loadMessagesFile(string filename) {
   write(sprintf("Reading messages file '%s'... ",filename));

   Stdio.File file    = Stdio.File();
   if (!file->open(filename, "r")) {
      write(sprintf("error!\n"));
      exit(0);
   }

   array text = file->read() / "\n";
   write(sprintf("- %d line(s) read\n",sizeof(text)));
   array keywords;

   foreach (text, string line) {
      int equalPos = search(line,"=");
      if (line!="" && equalPos>=0 && line[0]!='#') {
         string key = lower(String.trim_whites(line[0..equalPos-1]));
         string value = String.trim_whites(line[equalPos+1..]);
         messages[key] = value;
      }
   }
   return 1;
}


/**
 * Загружает сообщения messages[] из базы.
 * @param skinCode - код скина. Если не указан, то берется дефолтный.
 * @return хз что. Видимо, true - удачно, false - неудачно.
 */
int loadMessagesDB(void|string skinCode) {
	constant THIS_NAME = "loadMessagesDB";
	write("Reading messages table... ");

	int num_read = 0, num_ovr = 0;
	Sql.Sql db = game->sqlConnect();
	sql_result_t res;
	sql_row_t row;
	string query = "select distinct(name) from MESSAGES";
	res = db->big_query(query);
	while ( 0 != (row = res->fetch_row()) ) {
		num_read++;
		if (loadMessage(row[0], skinCode)) { num_ovr++; }
	}
   write("- %d message(s) read, %d ovr(s).\n", num_read, num_ovr);
   return 1;
} // int loadMessagesDB()

/**
 * Загружает сообщение из базы.
 * @param key - ключ (код) сообщения.
 * @param skinCode - код скина. Если не указан, то берется дефолтный.
 * @return false - было загружено оригинальное сообщение (ovr = false),
 * true - было загружено измененное сообщение (ovr = true).
 */
boolean loadMessage(string key, void|string skinCode) {
   BotSkin skin = zero_type(skinCode) ? getDefaultSkin() : skins[skinCode];

   boolean is_ovr = false;
   Sql.Sql db = game->sqlConnect();
   sql_result_t res;
   sql_row_t row;
   string query;

   query = sprintf("select name, value, ovr from MESSAGES where name = '%s' and skin_id = %d"
		" order by ovr desc limit 1", db->quote(key), skin->id);
   row = db->big_query(query)->fetch_row();
   if (row != 0) {
      string msg_key = lower(row[0]);
      string msg_value = row[1];
      is_ovr = 0 != (int)row[2];
      messages[msg_key] = msg_value;
   }
   return is_ovr;
} // boolean loadMessage()



int loadPhrases() {
	phrases = ([ ]);
   if (exportMode) {
      return loadPhrasesFile("phrases.txt");
   }
   return loadPhrasesDB();
}

int loadPhrasesFile(string filename) {
   write("Reading phrases file '%s'... ", filename);

   Stdio.File file    = Stdio.File();
   if (!file->open(filename, "r")) {
      write("error!\n");
      exit(0);
   }

   array phrases_text = file->read() / "\n";

   string currentKey = "";
   for (int i=0;i<sizeof(phrases_text);i++) {
      if (phrases_text[i]!="" && phrases_text[i][0]!='#') {
         if (phrases_text[i][0]=='!') {
            currentKey = phrases_text[i][1..];
//write(sprintf("currentKey=[%s]\n",currentKey));
            phrases[currentKey] = ({ });
         } else {
            Phrase p = Phrase(0, currentKey, phrases_text[i]);
            phrases[currentKey] += ({ p });
         }
      }
   }
   write("- %d key(s) read\n", sizeof(phrases));
   return 1;
} // int loadPhrasesFile()


/**
 * Загружает фразы (phrases.txt) из базы.
 * @param skinCode - код скина. Если не указан, будет взят дефолтный.
 * @return хз.
 */
int loadPhrasesDB(void|string skinCode) {
	constant THIS_NAME = "loadPhrasesDB";
	write("Reading phrases table... ");

	BotSkin skin = zero_type(skinCode) ? getDefaultSkin() : skins[skinCode];

	Sql.Sql db = game->sqlConnect();
	sql_result_t res;
	sql_row_t row;
	string query;

	int num_keys = 0, num_phrases = 0, num_ovr = 0;
	string prev_key = "";
	query = sprintf("select id, name, value, ovr, user_id from PHRASES where skin_id = %d and active <> 0 order by id", skin->id);
	res = db->big_query(query);
	while ( 0 != (row = res->fetch_row()) ) {
		int fidx = 0;
		int id = (int)row[fidx++];
		string key = row[fidx++];
		string value = row[fidx++];
		int ovr = (int)row[fidx++];
		int uid = (int)row[fidx++];
		if (zero_type(phrases[key])) {
			phrases[key] = ({ });
		}

		Phrase p = UNDEFINED;
		if (ovr > 0) {
			p = getPhraseByID(ovr);
		} else {
			p = getPhraseByID(id);
		}
		if (!zero_type(p)) {
			p->id = id;
			p->key = key;
			p->text = value;
			p->ovr = ovr;
			p->uid = uid;
		} else {
			p = Phrase(id, key, value, ovr, uid);
			phrases[key] += ({ p });
		}
		if (ovr) { num_ovr++; }
		num_phrases++;
		if (prev_key != key) {
			num_keys++;
			prev_key = key;
		}
	}

	write("- %d key(s) with %d phrase(s) read, %d ovr(s).\n", num_keys, num_phrases, num_ovr);
	return 1;
} // int loadPhrasesDB()


int loadPrompts() {
	prompts = ([ ]);
   if (exportMode) {
      return loadPromptsFile("prompts.txt");
   }
   return loadPromptsDB();
}

int loadPromptsFile(string filename) {
   write(sprintf("Reading prompts file '%s'... ",filename));

   Stdio.File file    = Stdio.File();
   if (!file->open(filename, "r")) {
      write(sprintf("error!\n"));
      exit(0);
   }

   array text = file->read() / "\n";
   write(sprintf("- %d line(s) read\n",sizeof(text)));
   array keywords;

   foreach (text, string line) {
      if (line!="" && search(line,"=")>=0 && line[0]!='#') {
         keywords=line/"="; keywords[0]=lower_case(keywords[0]);
         keywords[0]=String.trim_whites(keywords[0]);
         keywords[1]=String.trim_whites(keywords[1]);
         prompts[keywords[0]]=keywords[1];
      }
   }
   return 1;
} // int loadPromptsFile()


/**
 * Загружает подсказки (prompts.txt) из базы.
 * @param skinCode - код скина. Если не указан, будет взят дефолтный.
 * @return хз.
 */
int loadPromptsDB(void|string skinCode) {
	constant THIS_NAME = "loadPromptsDB";
	write("Reading prompts table... ");

	int num_read = 0, num_ovr = 0;
	Sql.Sql db = game->sqlConnect();
	sql_result_t res;
	sql_row_t row;
	string query = "select distinct(name) from PROMPTS";
	res = db->big_query(query);
	while ( 0 != (row = res->fetch_row()) ) {
		num_read++;
		if (loadPrompt(row[0], skinCode)) { num_ovr++; }
	}

	write("- %d prompt(s) read, %d ovr(s).\n", num_read, num_ovr);
	return 1;
} // int loadPromptsDB()


/**
 * Загружает подсказку роли из базы.
 * @param key - ключ (код) подсказки.
 * @param skinCode - код скина. Если не указан, то берется дефолтный.
 * @return false - было загружена оригинальная подсказка (ovr = false),
 * true - было загружено измененная подсказка (ovr = true).
 */
boolean loadPrompt(string key, void|string skinCode) {
	BotSkin skin = zero_type(skinCode) ? getDefaultSkin() : skins[skinCode];

	boolean is_ovr = false;

	Sql.Sql db = game->sqlConnect();
	sql_result_t res;
	sql_row_t row;
	string query;

	query = sprintf("select name, value, ovr from PROMPTS where name = '%s' and skin_id = %d"
		" order by ovr desc limit 1", db->quote(key), skin->id);
	res = db->big_query(query);
	while ( 0 != (row = res->fetch_row()) ) {
		string key = lower(row[0]);
		string value = row[1];
		is_ovr = 0 != (int)row[2];
		prompts[key] = value;
	}
	return is_ovr;
} // boolean loadPrompt()


int loadPoints() {
	points = ([ ]);
   if (exportMode) {
      return loadPointsFile("points.txt") & loadPointsFile("points.ovr");
   }
   return loadPointsDB();
}

int loadPointsFile(string filename) {
   write(sprintf("Reading points file '%s'... ",filename));

   Stdio.File file    = Stdio.File();
   if (!file->open(filename, "r")) {
      write(sprintf("error!\n"));
      exit(0);
   }

   array text = file->read() / "\n";
   file->close();

   array line;

   for (int i=0;i<sizeof(text);i++) {
      if (text[i]!="" && text[i][0]!='#') {
         line = map(text[i] / "=", String.trim_whites);
//write(sprintf("   %s=%s\n",line[0],line[1]));
         points[line[0]] = (int)line[1];
      }
   }
   write(sprintf("%d keys read\n",sizeof(points)));
   return 1;
} // int loadPointsFile()

/**
 * Загружает очки (points.txt) из базы.
 * @return хз.
 */
int loadPointsDB() {
	constant THIS_NAME = "loadPointsDB";
	write("Reading points table... ");

	int num_read = 0, num_ovr = 0;

	Sql.Sql db = game->sqlConnect();
	sql_result_t res;
	sql_row_t row;
	string query = "select distinct(name) from POINTS";
	res = db->big_query(query);
	while ( 0 != (row = res->fetch_row()) ) {
		num_read++;
		if (loadPointsKey(row[0])) { num_ovr++; }
	}

   write("- %d key(s) read, %d ovr(s).\n", num_read, num_ovr);
   return 1;
} // int loadPointsDB()

/**
 * Загружает очки из базы.
 * @param key - ключ (код) очков.
 * @return false - было загружена оригинальное значение (ovr = false),
 * true - было загружено измененное значение (ovr = true).
 */
boolean loadPointsKey(string key) {
	Sql.Sql db = game->sqlConnect();
   string query = sprintf("select name, value, ovr from POINTS where name = '%s' order by ovr desc limit 1",
		db->quote(key));
   sql_row_t row = db->big_query(query)->fetch_row();
   key = row[0];
   int value = (int)row[1];
   boolean is_ovr = 0 != (int)row[2];
   points[key] = value;
   return is_ovr;
} // int loadPointsDB()


int loadPieces() {
	pieces_map = ([ ]);
   if (exportMode) {
      return loadPiecesFile("pieces.cfg");
   }
   return loadPiecesDB();
}

int loadPiecesFile(string filename) {
   write(sprintf("Reading pieces file '%s'... ",filename));

   Stdio.File file = Stdio.File();
   if (!file->open(filename, "r")) {
      write("error!\n");
      exit(0);
   }

   array text = file->read() / "\n";
   write("- %d line(s) read\n", sizeof(text));
   array keys;
   string code;
   
   foreach (text, string line) {
      line = String.trim_whites(line);
      if (line == "" || line[0] == '#') { continue; }
      
      string key = String.trim_whites(lower((line / "=")[0]));
      string value = String.trim_whites((line / "=")[1]);
      pieces_map[key] = map(value / ",", String.trim_whites);
   }
   
   return 1;
} // int loadPieces()


/**
 * Загружает формы слов (pieces.cfg) из базы.
 * @param skinCode - код скина. Если не указан, будет взят дефолтный.
 * @return хз.
 */
int loadPiecesDB(void|string skinCode) {
	constant THIS_NAME = "loadPiecesDB";
	write("Reading pieces table... ");

	BotSkin skin = zero_type(skinCode) ? getDefaultSkin() : skins[skinCode];

	if (zero_type(skinCode)) { pieces_map = ([ ]); }

	Sql.Sql db = game->sqlConnect();
	sql_result_t res;
	sql_row_t row;
	string query;

	int num_read = 0, ovr_read = 0;
	query = sprintf("select name, value, ovr from PIECES where skin_id = %d order by name, ovr", skin->id);
	res = db->big_query(query);
	while ((row = res->fetch_row()) != 0) {
		string key = lower(row[0]);
		array(string) value = map(row[1] / ",", String.trim_whites);
		boolean is_ovr = 0 != (int)row[2];
		if (sizeof(value) != 3) {
			log(debug_log, sprintf("Invalid pieces length: %d. Must be 3.\n", sizeof(value)));
			exit(1);
		}
		pieces_map[key] = value;
		num_read++;
		if (is_ovr) { ovr_read++; }
	}

	write("- %d key(s) read, %d ovr(s).\n", num_read, ovr_read);
	return 1;
} // int loadPiecesDB()


/**
 * Загружает группы пользователей.
 * @param skinCode - код скина. Если не указан, будет взят дефолтный.
 * @return хз.
 */
int loadUserGroups(void|string skinCode) {
	constant THIS_NAME = "loadUserGroups";
	write("Reading user groups table... ");

	BotSkin skin = zero_type(skinCode) ? getDefaultSkin() : skins[skinCode];

	if (zero_type(skinCode)) {
		userGroups = ([ ]);
		userGroupsByID = ([ ]);
	}

	Sql.Sql db = game->sqlConnect();
	sql_result_t res;
	sql_row_t row;
	string query;

	int num_read = 0;
	query = "select id, code from USER_GROUPS";
	res = db->big_query(query);
	while ((row = res->fetch_row()) != 0) {
		int fidx = 0;
		int id = (int)row[fidx++];
		string code = row[fidx++];
		UserGroup g = UserGroup(id, code, "");
		userGroups[code] = g;
		userGroupsByID[id] = g;

		// Загрузить названия.
		loadUserGroupNames(g, skinCode);

		// Загрузить в кеш права на добавление/удаление пользователей в/из групп.
		loadUserGroupAccessRights(g, db);

		num_read++;
	}

	write("- %d group(s) read.\n", num_read);
	return 1;
}


/**
 * Загружает из базы названия группы пользователей.
 * @param ug - группа пользователей.
 * @param skinCode - код скина. Если не указан, будет взят дефолтный.
 */
void loadUserGroupNames(UserGroup ug, void|string skinCode) {
	BotSkin skin;
	if (zero_type(skinCode)) {
		skin = getDefaultSkin();
		ug->name_1 = ug->name_2 = ug->name_3 = ug->description = "";
	} else {
		skin = skins[skinCode];
	}
	Sql.Sql db = game->sqlConnect();
	string query = sprintf("select name_1, name_2, name_3, description from USER_GROUPS_NAMES"
		" where group_id = %d and skin_id = %d", ug->id, skin->id);
	sql_row_t row = db->big_query(query)->fetch_row();
	if (row != 0) {
		int fidx = 0;
		ug->name_1 = row[fidx++];
		ug->name_2 = row[fidx++];
		ug->name_3 = row[fidx++];
		ug->description = row[fidx++];
	}
} // void loadUserGroupNames()

/**
 * Загружает из базы в кеш права доступа к группе пользователей.
 * @param ug - группа.
 * @param conn - соединение с базой. Если не указано, будет открыто новое.
 * @return сколько прав загружено.
 */
int loadUserGroupAccessRights(UserGroup ug, void|Sql.Sql conn) {
	ug->clearAccessCache();
	Sql.Sql db = zero_type(conn) ? game->sqlConnect() : conn;
	string query = sprintf("select owner_type, owner_id, may_add, may_remove"
		" from USER_GROUPS_RIGHTS where group_id = %d", ug->id);
	sql_result_t res_acl = db->big_query(query);
	sql_row_t row_acl;
	int perms_read = 0;
	while ( 0 != (row_acl = res_acl->fetch_row()) ) {
		perms_read++;
		int fidx_acl = 0;
		int owner_type = (int)row_acl[fidx_acl++];
		int owner_id = (int)row_acl[fidx_acl++];
		int may_add = (int)row_acl[fidx_acl++];
		int may_remove = (int)row_acl[fidx_acl++];
/*
write("[%s]: row_acl=%O\n", ug->name, row_acl);
write("[%s]: owner_type=%s, owner_id=%d, may_add=%s, may_remove=%s\n", ug->name, 
	OWNER_GROUP == owner_type ? "OWNER_GROUP" : OWNER_USER == owner_type ? "OWNER_USER" : (string)owner_type,
	owner_id,
	ACL_ADD == may_add ? "ACL_ADD" : ACL_NO_ADD == may_add ? "ACL_NO_ADD" : (string)may_add,
	ACL_REMOVE == may_remove ? "ACL_REMOVE" : ACL_NO_REMOVE == may_remove ? "ACL_NO_REMOVE" : (string)may_remove
	);
*/
		AccessType at = AT_INVALID;
		if (OWNER_GROUP != owner_type && OWNER_USER != owner_type) {
			logError(sprintf("PANIC: Unknown owner type for user group '%s': %d", ug->name, owner_type));
			exit(1);
		}
		if (may_add != 0) {
//write("[%s]: may_add != 0 (%d), adding owner_id %d\n", ug->name, may_add, owner_id);
			switch (may_add) {
				case ACL_ADD:		at = AT_ALLOW; break;
				case ACL_NO_ADD:	at = AT_DENY; break;
				default:
					logError(sprintf("PANIC: Unknown may_add value for user group '%s': %d", ug->name, may_add));
					exit(1);
			}
			ug->putAccess(at, "ACL_ADD", owner_type, owner_id);
		}
		if (may_remove != 0) {
//write("[%s]: may_remove != 0 (%d), adding owner_id %d\n", ug->name, may_remove, owner_id);
			switch (may_remove) {
				case ACL_REMOVE:		at = AT_ALLOW; break;
				case ACL_NO_REMOVE:	at = AT_DENY; break;
				default:
					logError(sprintf("PANIC: Unknown may_remove value for user group '%s': %d", ug->name, may_remove));
					exit(1);
			}
			ug->putAccess(at, "ACL_REMOVE", owner_type, owner_id);
		}
	} // while ( 0 != (row_acl = res_acl->fetch_row()) )
/*
write("[%s (id=%d)]: %d access right(s) read: allowed groups=[add=%d, remove=%d], "
	"denied groups=[add=%d, remove=%d], allowed users=[add=%d, remove=%d], "
	"denied users=[add=%d, remove=%d]\n", cmd->name, cmd->id, perms_read,
	sizeof(ug->allowed_groups["ACL_ADD"]),	sizeof(ug->allowed_groups["ACL_REMOVE"]),
	sizeof(ug->denied_groups["ACL_ADD"]), sizeof(ug->denied_groups["ACL_REMOVE"]),
	sizeof(ug->allowed_users["ACL_ADD"]), sizeof(ug->allowed_users["ACL_REMOVE"]),
	sizeof(ug->denied_users["ACL_ADD"]), sizeof(ug->denied_users["ACL_REMOVE"])
	);
*/
	return perms_read;
} // int loadUserGroupAccessRights();



int loadArtifacts() {
	artifacts = ([ ]);
   int rc = 1;
   if (exportMode) {
      rc = loadArtifactsFile("artifacts.cfg")
         && loadArtifactsFile("artifacts.ovr");
      if (rc) {
         // generate commands for using artifacts (if any).
         map(indices(artifacts), generateArtifactCommand);
      }
   } else {
      rc = loadArtifactsDB();
      if (rc) {
         loadArtifactCommands();
      }
   }
   return rc;
}

int loadArtifactsFile(string filename) {
   constant THIS_NAME = "loadArtifactsFile";
   write(sprintf("Reading artifacts file '%s'... ",filename));

   Stdio.File file = Stdio.File();
   if (!file->open(filename, "r")) {
      write("error!\n");
      exit(0);
   }

   array text = file->read() / "\n";
   write("- %d line(s) read\n", sizeof(text));
   array keys;
   string code;

   foreach (text, string line) {
      line = String.trim_whites(line);
      if (line == "" || line[0] == '#') { continue; }
      
      string key = String.trim_whites(lower((line / "=")[0]));
      string value = String.trim_whites((line / "=")[1]);
//write("key=%s value=%s\n",key,value);
      switch (key) {
         case "artifact":
            code = lower(value);
            if (!artifacts[code]) {
               artifacts[code] = Artifact(code);
            }
            break;

         case "name":
            artifacts[code]->name = value;
            break;

         case "name_pl":
            artifacts[code]->name_pl = value;
            break;

         case "price":
            artifacts[code]->price = (int)value;
            break;

         case "synonyms":
            artifacts[code]->synonyms = map(map(value / ",", String.trim_whites), lower);
            break;

         case "pieces":
            artifacts[code]->pieces = map(value / ",", String.trim_whites);
            pieces_map[code] = artifacts[code]->pieces;
            break;
         case "quantitydivider":
            ArtifactQuantityDivider qd = ArtifactQuantityDivider(value);
            if (qd->getType() == AQD_INVALID) {
               write("Invalid quantityDivider for artifact %s: %s\n", code, value > "" ? value : "<empty string>");
               exit(1);
            } else {
               artifacts[code]->quantityDivider = qd;
            }
            break;
         case "enabled":
            artifacts[code]->enabled = "yes" == lower(value);
            break;

         case "permissions":
            array(string) a = map(value / ",", String.trim_whites);
            // Очистить уже имеющиеся разрешения, если загружается artifacts.ovr
            artifacts[code]->permissions = ArtifactPermissions();
            int first = 1;
            foreach(a, string p) {
               ArtifactPermissionsType t = getArtifactPermissionsType(p);
               if (t == APT_INVALID) {
                  write("%s: Invalid permission for artefact %s: %s\n", THIS_NAME, code, p > "" ? p : "<empty string>");
                  if (p > "") { exit(1); }
               }
               if (first) {
                  first = 0;
                  // Удалить умолчальные разрешения.
                  artifacts[code]->permissions->remove("*", APT_DENY);
               }
//write("putting permission for '%s': '%s'\n", code, p);
               artifacts[code]->permissions->put(p);
            }
            break;

         case "expires":
            artifacts[code]->expires = "yes" == lower(value);
            break;

         case "command":
            artifacts[code]->generateCommand = "yes" == lower(value);
            break;

         case "disposable":
            artifacts[code]->disposable = "yes" == lower(value);
            break;
      } // switch (key)
   } // foreach (text, string line)

   return 1;
} // int loadArtifactsFile(string filename)

/**
 * Загружает артефакты из базы.
 * @param skinCode - код скина. Если не указан, будет взят дефолтный.
 * @return true - удачно, false - неудачно.
 */
int loadArtifactsDB(void|string skinCode) {
	constant THIS_NAME = "loadArtifactsDB";
	write("Reading artifacts table... ");

	Sql.Sql db = game->sqlConnect();
	sql_result_t res;
	sql_row_t row;
	string query;
	int num_read = 0, num_ovr = 0;

	query = "select code, ovr from ARTIFACTS order by code, ovr";
	res = db->big_query(query);
	while ( 0 != (row = res->fetch_row()) ) {
		string code = row[0];
		boolean is_ovr = 0 != (int)row[1];
		loadArtifact(code, skinCode);
		num_read++;
		if (is_ovr) { num_ovr++; }
	}

	write("- %d artifact(s) read, %d ovr(s).\n", sizeof(artifacts), num_ovr);
	return 1;
} // int loadArtifactsDB()

/**
 * Загружает артефакт из базы.
 * @param code - код артефакта.
 * @param skinCode - код скина. Если не указан, будет взят дефолтный.
 */
void loadArtifact(string code, void|string skinCode) {
	Sql.Sql db = game->sqlConnect();
	sql_result_t res;
	sql_row_t row;
	string query;

	query = sprintf("select id, code, price, quantityDivider, enabled, permissions, command, expires, disposable"
		" from ARTIFACTS where code = '%s' order by ovr desc limit 1", db->quote(code));
	res = db->big_query(query);
	while ( 0 != (row = res->fetch_row()) ) {
		int field_idx = 0;
		int artifactID = (int)row[field_idx++];
		string code = row[field_idx++];
		//string name = row[field_idx++];
		//string name_pl = row[field_idx++];
		int price = (int)row[field_idx++];
		string quantityDivider = row[field_idx++];
		boolean enabled = 0 != (int)row[field_idx++];
		array(string) permissions = map(row[field_idx++] / ",", String.trim_whites);
		boolean generateCommand = 0 != (int)row[field_idx++];
		boolean expires = 0 != (int)row[field_idx++];
		boolean disposable = 0 != (int)row[field_idx++];
	   
		ArtifactQuantityDivider aqd = ArtifactQuantityDivider(quantityDivider);
		if (AQD_INVALID == aqd->getType()) {
			logError(sprintf("PANIC: loadArtifact: artifact '%s': invalid quantity divider: '%s'\n", code, aqd->getValue()));
			exit(1);
		}

		Artifact a = artifacts[code] || Artifact(code);
		a->id = artifactID;
		//a->name = name;
		//a->name_pl = name_pl;
		a->price = price;
		a->quantityDivider = aqd;
		a->enabled = enabled;
		// Удалить умолчальные разрешения, если они заданы явно,
		// или если это второе чтение параметров артефакта (ovr = true).
		if (sizeof(permissions) > 0 || !zero_type(artifacts[code])) {
			a->permissions->remove("*", APT_DENY);
			map(permissions, a->permissions->put);
		}
		a->generateCommand = generateCommand;
		a->expires = expires;
		a->disposable = disposable;

		// Загрузить названия артефакта.
		loadArtifactNames(a, skinCode);

		// Загрузить синонимы артефакта.
		loadArtifactAliases(a, skinCode);

		// Загрузить формы слов артефакта.
		loadArtifactPieces(a, skinCode);

		artifacts[code] = a;
	}
} // void loadArtifact()


/**
 * Загружает из базы названия артефакта.
 * @param a - артефакт.
 * @param skinCode - код скина. Если не указан, то будет взят дефолтный.
 */
void loadArtifactNames(Artifact a, void|string skinCode) {
	BotSkin skin = zero_type(skinCode) ? getDefaultSkin() : skins[skinCode];
	Sql.Sql db = game->sqlConnect();
	sql_row_t row;
	string query;
	
	query = sprintf("select name, name_pl from ARTIFACTS_NAMES where art_code = '%s' and skin_id = %d"
		" order by ovr desc limit 1", db->quote(a->code), skin->id);
	row = db->big_query(query)->fetch_row();
	if (row != 0) {
		a->name = row[0];
		a->name_pl = row[1];
	}
} // void loadArtifactNames()

/**
 * Загружает из базы синонимы артефакта.
 * @param a - артефакт.
 * @param skinCode - код скина. Если не указан, то будет взят дефолтный.
 */
void loadArtifactAliases(Artifact a, void|string skinCode) {
	a->synonyms = ({ });
	BotSkin skin = zero_type(skinCode) ? getDefaultSkin() : skins[skinCode];
	Sql.Sql db = game->sqlConnect();
	sql_result_t res;
	sql_row_t row;
	string query;
	boolean first_row = true, has_ovr = false;
	
	query = sprintf("select name, ovr from ARTIFACTS_ALIASES where art_code = '%s' and skin_id = %d"
		" order by ovr desc", db->quote(a->code), skin->id);
	res = db->big_query(query);
	while ( 0 != (row = res->fetch_row()) ) {
		if (first_row) {
			first_row = false;
			has_ovr = 0 != (int)row[1];
		}
		boolean is_ovr = 0 != (int)row[1];
		if (has_ovr && !is_ovr) { break; }
		a->synonyms += ({ row[0] });
	}
} // void loadArtifactAliases()

/**
 * Загружает из базы формы названий артефакта.
 * @param a - артефакт.
 * @param skinCode - код скина. Если не указан, то будет взят дефолтный.
 */
void loadArtifactPieces(Artifact a, void|string skinCode) {
	BotSkin skin = zero_type(skinCode) ? getDefaultSkin() : skins[skinCode];
	Sql.Sql db = game->sqlConnect();
	sql_row_t row;
	string query;
	
	query = sprintf("select value from PIECES where name = '%s' and skin_id = %d order by ovr desc limit 1",
		db->quote(a->code), skin->id);
	row = db->big_query(query)->fetch_row();
	if (row != 0) {
		a->pieces = map(row[0] / ",", String.trim_whites);
	}
	pieces_map[a->code] = a->pieces;
} // void loadArtifactPieces()

/**
 * Загружает команды применения артефактов.
 * @return количество загруженых команд.
 */
int loadArtifactCommands() {
   // Удалить команды артефактов из commands[].
   foreach (indices(artifacts), string code) {
      if (artifacts[code]->generateCommand) { m_delete(commands, code); }
   }
   write("Reading artifact commands table... ");
   int commands_loaded = loadCommandsByGroup(settings["shopcommandgroup"]->value);
   write("- %d artifact command(s) read.\n", commands_loaded);
   return commands_loaded;
}

/**
 * Генерирует отдельную команду для использования артефакта.
 * @param code - код артефакта.
 */
void generateArtifactCommand(string code) {
//write("DEBUG: Generating artifact command: %s\n", code);
   Artifact a = artifacts[code];
   int min_level = 0;
   if (!zero_type(commands[code])) {
      log(debug_log, sprintf("ERROR: generateArtifactCommand(): command '%s' already exist: %O\n", code, commands[code]));
      return; //exit(1);
   }
   if (!a->generateCommand) {
//write("DEBUG: Artifact '%s' has generateCommand = false, skipping.\n", code);
      return;
   }
/*
   if (!a->enabled) {
//write("DEBUG: Artifact '%s' is not enabled, skipping.\n", code);
      return;
   }
   if (sizeof(a->permissions->getAllAllowed()) < 1) {
//write("DEBUG: No permissions given for artifact '%s', skipping.\n", code);
      return;
   }
*/

//write("DEBUG: Creating artifact command: %s\n", code);
   Commands cmd = Commands();
   string CG_SHOP = settings["shopcommandgroup"]->value; // command group name
   if (zero_type(commandGroups[CG_SHOP])) {
     commandGroups[CG_SHOP] = getMessage("shop_command_group_name"); //settings["shopcommandgroupname"]->value;
   }
   cmd->group  = CG_SHOP;
   cmd->source = "m";
   cmd->synonimes = a->synonyms; //({ code }) + a->synonyms;
   cmd->level = UL_USER;
   commands[code] = cmd;
//write("DEBUG: Command generated: %s\n", code);
} // void generateArtifactCommand()


/**
 * Удаляет команду для использования артефакта.
 * @param code - код артефакта.
 */
void removeArtifactCommand(string code) {
   throw( ({ "Not implemented.\n", backtrace() }) );
} // void removeArtifactCommand()










/**
 * Меняет текущий скин.
 * @param skinCode - код скина.
 */
void setCurrentSkin(string skinCode) {
	constant THIS_NAME = "setCurrentSkin";
log(debug_log, sprintf("%s: changing skin from '%s' to '%s'", THIS_NAME, settings["skin"]->value, skinCode));
	//if (settings["skin"]->value == skinCode) return;
	if (zero_type(skins[skinCode])) {
		error("Skin not found: %s\n", skinCode); // throw
	}
	settings["skin"]->value = skinCode;
	loadUserGroupsNames(skinCode);
	loadSettingsDescriptions(skinCode);
	loadRolesNames(skinCode);
	loadRolesCommandsAliases(skinCode);
	loadCommandGroupsNames(skinCode);
	loadCommandSources(skinCode);
	loadCommandsAliases(skinCode);
	loadMessagesDB(skinCode);
	loadPiecesDB(skinCode);
	loadPhrasesDB(skinCode);
	loadPromptsDB(skinCode);
	loadArtifactsNames(skinCode);
	loadArtifactsAliases(skinCode);
} // void setCurrentSkin()

/**
 * Загружает названия групп пользователей.
 * @param skinCode - код скина.
 */
void loadUserGroupsNames(string skinCode) {
	map(values(userGroups), loadUserGroupNames, skinCode);
} // void loadUserGroupsNames()

/**
 * Загружает описания настроек бота.
 * @param skinCode - код скина.
 */
void loadSettingsDescriptions(string skinCode) {
	map(values(settings), loadSettingDescription, skinCode);
} // void loadSettingsDescriptions()

/**
 * Загружает названия ролей.
 * @param skinCode - код скина.
 */
void loadRolesNames(string skinCode) {
	map(values(roles), loadRoleName, skinCode);
}

/**
 * Загружает синонимы команд ролей.
 * @param skinCode - код скина.
 */
void loadRolesCommandsAliases(string skinCode) {
	foreach (values(roles), Roles r) {
		foreach (values(r->commands), Roles.Commands cmd) {
			loadRoleCommandAliases(r, cmd, skinCode);
		}
	}
}

/**
 * Загружает названия групп команд бота.
 * @param skinCode - код скина.
 */
void loadCommandGroupsNames(string skinCode) {
	BotSkin skin = skins[skinCode];
	
	Sql.Sql db = game->sqlConnect();
	sql_result_t res;
	sql_row_t row;
	string query;
	
	query = sprintf("select code, description from COMMANDS_GROUPS where skin_id = %d", skin->id);
	res = db->big_query(query);
	while ( 0 != (row = res->fetch_row()) ) {
		commandGroups[row[0]] = row[1];
	}
} // void loadCommandGroupsNames()

/**
 * Загружает синонимы команд бота.
 * @param skinCode - код скина.
 */
void loadCommandsAliases(string skinCode) {
	map(values(commands), loadCommandAliases, skinCode);
} // void loadCommandsAliases()

/**
 * Загружает названия артефактов.
 * @param skinCode - код скина.
 */
void loadArtifactsNames(string skinCode) {
	map(values(artifacts), loadArtifactNames, skinCode);
}

/**
 * Загружает синонимы артефактов.
 * @param skinCode - код скина.
 */
void loadArtifactsAliases(string skinCode) {
	map(values(artifacts), loadArtifactAliases, skinCode);
}







void loadBannerFile() {
	string filename = "banner.txt";
	Stdio.File file = Stdio.File();
	if (!file->open(filename, "r")) {
		irc->message(settings["gamechannel"]->value,settings["color.error"]->value,getMessage("error_reading_banner_file"));
		return;
	}
	banner = (file->read() / "\n")[0];
	file->close();
}

void loadBanner() {
	banner = loadChannelString(CHS_BANNER);
}

/**
 * Загружает топик игрового канала из базы.
 */
void loadTopic() {
	topic = loadChannelString(CHS_TOPIC);
}

/**
 * Загружает последний топик/баннер из базы.
 * @param string_type - что грузить.
 * @return загруженную строку.
 */
string loadChannelString(ChannelStringType string_type) {
	Sql.Sql db = game->sqlConnect();
	string query = sprintf("select text from CHANNEL_STRINGS where string_type = %d and skin_id = %d"
		" order by id desc limit 1", string_type, getCurrentSkin()->id);
	sql_row_t row = db->big_query(query)->fetch_row();
	if (row == 0) {
		query = sprintf("select text from CHANNEL_STRINGS where string_type = %d and skin_id = %d"
			" order by id desc limit 1", string_type, getDefaultSkin()->id);
		row = db->big_query(query)->fetch_row();
	}
	return row != 0 ? row[0] : "";
} // string loadChannelString()

/**
 * Сохраняет топик/баннер в базу.
 * @param string_type - тип строки.
 * @param text - текст.
 * @param userID - ID задавшего юзера.
 */
void saveChannelString(ChannelStringType string_type, string text, int userID) {
	Sql.Sql db = game->sqlConnect();
	string query = sprintf("insert into CHANNEL_STRINGS(string_type,user_id,text,skin_id) values(%d,%d,'%s',%d)", 
		string_type, userID, db->quote(text), getCurrentSkin()->id);
	db->big_query(query);
	
	// Update settings[]
	switch (string_type) {
		case CHS_BANNER:
			banner = text;
			break;
		case CHS_TOPIC:
			topic = text;
			break;
		default:
			// FIXME: Should an exception be thrown?
			break;
	}
} // void saveChannelString()


/**
 * Сохраняет текущие настройки артефактов в файл.
 */
void saveArtifacts() {
log(debug_log,"game->saveArtifacts()");
	Stdio.File file = Stdio.File();
	if (!file->open("artifacts.ovr", "cwt")) {
		irc->message(settings["gamechannel"]->value, settings["color.error"]->value, getMessage("error_writing_artifacts_ovr"));
		log(debug_log,sprintf("Error writing file artifacts.ovr!"));
		return;
	}
	foreach(indices(artifacts), string code) {
		Artifact a = artifacts[code];
		file->write(sprintf("artifact = %s\n", code));
		file->write(sprintf("name = %s\n", a->name));
		file->write(sprintf("name_pl = %s\n", a->name_pl));
		file->write(sprintf("price = %d\n", a->price));
		file->write(sprintf("synonyms = %s\n", a_join(a->synonyms, ", ")));
		file->write(sprintf("pieces = %s\n", a_join(a->pieces, ", ")));
		file->write(sprintf("quantityDivider = %s\n", a->quantityDivider->getValue()));
		file->write(sprintf("enabled = %s\n", a->enabled ? "yes" : "no"));
		string pa = m_join(a->permissions->getAllAllowed(), ",", ":");
		string pd = a_join(indices(a->permissions->getAllDenied()), ",");
		if (pd > "") pa += (pa > "" ? ", " : "") + "!" + pd;
		file->write(sprintf("permissions = %s\n", pa));
		file->write(sprintf("command = %s\n", a->generateCommand ? "yes" : "no"));
		file->write(sprintf("expires = %s\n", a->expires ? "yes" : "no"));
		file->write(sprintf("disposable = %s\n", a->disposable ? "yes" : "no"));
		file->write("\n");
	}
	file->close();
} // void saveArtifacts()


/**
 * Сохраняет параметры артефакта в базу.
 * @param code - код артефакта.
 * @param uid - ID оператора, поменявшего параметры артефакта.
 */
void saveArtifact(string code, int uid) {
	constant THIS_NAME = "saveArtifact";

	BotSkin skin = getCurrentSkin();
	Artifact a = artifacts[code];
	if (zero_type(a)) { return; }
	string pa = m_join(a->permissions->getAllAllowed(), ",", ":");
	string pd = a_join(indices(a->permissions->getAllDenied()), ",");
	if (pd > "") pa += (pa > "" ? "," : "") + "!" + pd;
	mixed err = catch {
		Sql.Sql db = game->sqlConnect();
		sql_result_t res;
		sql_row_t row;
		string query;

		// параметры.
		query = sprintf("delete from ARTIFACTS where code = '%s' and ovr <> 0", db->quote(code));
		db->big_query(query);
		query = sprintf("insert into ARTIFACTS(code, price, quantityDivider, enabled, permissions, command,"
			" expires, disposable, ovr, user_id) values('%s', %d, '%s', %d, '%s', %d, %d, %d, 1, %d)",
			db->quote(code), a->price, db->quote(a->quantityDivider->getValue()), a->enabled, db->quote(pa),
			a->generateCommand, a->expires, a->disposable, uid);
log(debug_log, sprintf("%s: saving artifact parameters: code='%s': query=[%s]", THIS_NAME, code, query));
		db->big_query(query);

		// названия.
		query = sprintf("delete from ARTIFACTS_NAMES where art_code = '%s' and ovr <> 0", db->quote(code));
		db->big_query(query);
		query = sprintf("insert into ARTIFACTS_NAMES(art_code, name, name_pl, skin_id, ovr, user_id)"
			" values('%s', '%s', '%s', %d, 1, %d)", db->quote(code), db->quote(a->name),
			db->quote(a->name_pl), skin->id, uid);
log(debug_log, sprintf("%s: saving artifact names: code='%s': query=[%s]", THIS_NAME, code, query));
		db->big_query(query);

		// формы слов.
		query = sprintf("delete from PIECES where name = '%s' and ovr <> 0", db->quote(code));
		db->big_query(query);
		query = sprintf("insert into PIECES(name,value,skin_id,ovr,user_id) values('%s','%s',%d,1,%d)",
			db->quote(code), db->quote(a->pieces * ","), skin->id, uid);
log(debug_log, sprintf("%s: saving artifact pieces: code='%s': query=[%s]", THIS_NAME, code, query));
		db->big_query(query);

		// синонимы.
		query = sprintf("delete from ARTIFACTS_ALIASES where art_code = '%s' and skin_id = %d and ovr <> 0",
			db->quote(code), skin->id);
		db->big_query(query);
		foreach (a->synonyms, string syn) {
			query = sprintf("insert into ARTIFACTS_ALIASES(art_code, name, skin_id, ovr, user_id)"
				" values('%s', '%s', %d, 1, %d)", db->quote(code), db->quote(syn), skin->id, uid);
			db->big_query(query);
		}
	}; // mixed err
	if (err) {
		logError(sprintf("ERROR: %s() failed: code='%s':\n%s", THIS_NAME, code, describe_backtrace(err)));
		irc->message(settings["gamechannel"]->value, settings["color.error"]->value,
			getMessage("error_saving_artifact"), code);
	}
} // void saveArtifact()


/**
 * Сохраняет текущие настройки очков в файл.
 */
void savePointsFile() {
//log(debug_log,"game->savePoints()");
	string ovr_file = "points.ovr";
	Stdio.File file = Stdio.File();
	if (!file->open(ovr_file, "cwt")) {
		irc->message(settings["gamechannel"]->value, settings["color.error"]->value, getMessage("error_writing_points_ovr"), ovr_file);
		log(debug_log, sprintf("Error writing file %s!", ovr_file));
		return;
	}
	foreach(indices(points), string key) {
		file->write(sprintf("%s = %d\n", key, points[key]));
	}
	file->close();
} // void savePointsFile()

/**
 * Сохраняет текущие настройки очков в базу.
 * @param key - ключ из points[].
 * @param uid - ID оператора, изменившего очки.
 * @throws если что не так.
 */
void savePoints(string key, int uid) {
	Sql.Sql db = game->sqlConnect();
	string query;
	query = sprintf("delete from POINTS where name = '%s' and ovr <> 0", db->quote(key));
	db->big_query(query);
	query = sprintf("insert into POINTS(name,value,ovr,user_id) values('%s',%d,1,%d)", db->quote(key),
		points[key], uid);
	db->big_query(query);
} // void savePoints()


/**
 * Сохраняет параметры роли в базу.
 * @param code - код роли.
 * @param uid - ID оператора, поменявшего параметры роли.
 */
void saveRole(string code, int uid) {
	BotSkin skin = getCurrentSkin();
	Roles r = roles[code];
	Sql.Sql db = game->sqlConnect();
	string query;

	// основные параметры.
	query = sprintf("delete from ROLES where role_id = '%s' and ovr <> 0", db->quote(code));
	db->big_query(query);
	query = sprintf("insert into ROLES(role_id, players_min, voice_level, repeat_order, ovr, user_id)"
		" values('%s', %d, %d, %d, 1, %d)", db->quote(code), r->playersMin, r->voiceLevel,
		r->maxRepeatOrder, uid);
log(debug_log, sprintf("saveRole: query=[%s]", query));
	db->big_query(query);

	// название.
	query = sprintf("delete from ROLES_NAMES where role_code = '%s' and skin_id = %d and ovr <> 0",
		db->quote(code), skin->id);
	db->big_query(query);
	query = sprintf("insert into ROLES_NAMES(role_code,name,skin_id,ovr,user_id) values('%s','%s',%d,1,%d)",
		db->quote(code), db->quote(r->name), skin->id, uid);
	db->big_query(query);

	// делители уровней.
	query = sprintf("delete from ROLES_LEVELS where role_code = '%s' and ovr <> 0", db->quote(code));
	db->big_query(query);
	array(int) ld = r->levelDividers;
	for (int i = 2; i < sizeof(ld); i++) {
		query = sprintf("insert into ROLES_LEVELS(role_code,level,divider,ovr,user_id) values('%s',%d,%d,1,%d)",
			db->quote(code), i, ld[i], uid);
log(debug_log, sprintf("saveRole: query=[%s]", query));         
		db->big_query(query);
	}
	
	// фичи.
	query = sprintf("delete from ROLES_FEATURES where role_code = '%s' and ovr <> 0", db->quote(code));
	db->big_query(query);
	foreach (sort(indices(r->features)), string feature) {
		query = sprintf("insert into ROLES_FEATURES(role_code, feature_code, level, ovr, user_id)"
			" values('%s', '%s', %d, 1, %d)", db->quote(code), db->quote(feature), r->features[feature], uid);
log(debug_log, sprintf("saveRole: query=[%s]", query));         
		db->big_query(query);
	}
} // void saveRole()

void saveRoles() {
	map(indices(roles), saveRole, -1);
}

void saveRolesFile() {
log(debug_log,"game->saveRoles()");
	Stdio.File file = Stdio.File();
	if (!file->open("roles.ovr", "cwt")) {
		irc->message(settings["gamechannel"]->value,settings["color.error"]->value,getMessage("roles_ovr_writing_error"));
		log(debug_log,sprintf("Error writing file roles.ovr!"));
		return;
	}
	foreach(indices(roles), string role) {
		file->write(sprintf("role  = %s\n",role));
		file->write(sprintf("name  = %s\n",roles[role]->name));
		file->write(sprintf("playersMin  = %d\n",(int)roles[role]->playersMin));
		file->write(sprintf("repeatOrder = %d\n",(int)roles[role]->maxRepeatOrder));
		file->write(sprintf("voiceLevel  = %d\n",(int)roles[role]->voiceLevel));
		string div = "";
		for (int i = 2;i<=(int)settings["maxlevel"]->value;i++) {
			if (div!="") div += ", ";
			div += (string)roles[role]->levelDividers[i];
		}
		file->write(sprintf("levelsDivider = %s\n",div));
	}
	file->close;
}



/**
 * Сохраняет текст сообщения из messages[] в базу.
 * @param key - ключ сообщения.
 * @param uid - ID оператора, изменившего сообщение.
 */
void saveMessage(string key, int uid) {
	BotSkin skin = getCurrentSkin();
	Sql.Sql db = game->sqlConnect();
	sql_row_t row;
	string query;
	query = sprintf("delete from MESSAGES where name = '%s' and skin_id = %d and ovr <> 0", db->quote(key), skin->id);
	db->big_query(query);
	query = sprintf("insert into MESSAGES(name,value,skin_id,ovr,user_id) values('%s','%s',%d,1,%d)",
		db->quote(key), db->quote(getMessage(key)), skin->id, uid);
	db->big_query(query);
} // void saveMessage()

/**
 * Удаляет сообщение из messages[] и из базы.
 * @param key - ключ сообщения.
 */
void deleteMessage(string key) {
	BotSkin skin = getCurrentSkin();
	Sql.Sql db = game->sqlConnect();
	string query = sprintf("delete from MESSAGES where name = '%s' and skin_id = %d", db->quote(key), skin->id);
	db->big_query(query);
	m_delete(messages, key);
} // void deleteMessage()





/**
 * Сохраняет текст фразы из phrases[] в базу.
 * @param p - фраза.
 * @param uid - ID оператора, изменившего сообщение.
 */
void savePhrase(Phrase p, int uid) {
	BotSkin skin = getCurrentSkin();
	Sql.Sql db = game->sqlConnect();
	sql_row_t row;
	string query;
	if (p->id > 0) {
		if (p->ovr > 0) {
			query = sprintf("update PHRASES set value = '%s' where id = %d", db->quote(p->text), p->id);
			db->big_query(query);
		} else {
			query = sprintf("delete from PHRASES where ovr = %d", p->id);
			db->big_query(query);

			query = sprintf("insert into PHRASES(name, value, skin_id, ovr, user_id, active)"
				" values('%s', '%s', %d, %d, %d, 1)", db->quote(p->key), db->quote(p->text),
				skin->id, p->id, uid);
			db->big_query(query);

			p->ovr = p->id;
			p->uid = uid;
			query = sprintf("select id from PHRASES where name = '%s' and skin_id = %d and ovr = %d"
				" and active <> 0 order by id desc limit 1", db->quote(p->key), skin->id, p->id);
			row = db->big_query(query)->fetch_row();
			p->id = (int)row[0];
		}
	} else {
		query = sprintf("insert into PHRASES(name, value, skin_id, ovr, user_id, active)"
			" values('%s', '%s', %d, 0, %d, 1)", db->quote(p->key), db->quote(p->text),
			skin->id, uid);
		db->big_query(query);

		p->ovr = 0;
		p->uid = uid;
		query = sprintf("select id from PHRASES where name = '%s' and skin_id = %d and user_id = %d"
			" and active <> 0 order by id desc limit 1", db->quote(p->key), skin->id, uid);
		row = db->big_query(query)->fetch_row();
		p->id = (int)row[0];
	}
} // void savePhrase()

/**
 * Удаляет фразу из phrases[] и из базы.
 * @param p - фраза.
 */
void deletePhrase(Phrase p) {
	Sql.Sql db = game->sqlConnect();
	// Удаляем эту фразу, а также все фразы, которые ее оверрайдят.
	string query = sprintf("delete from PHRASES where id = %d or ovr <> 0 and ovr = %d", p->id, p->id);
	db->big_query(query);

	if (!zero_type(phrases[p->key])) {
		phrases[p->key] -= ({ p });
		if (sizeof(phrases[p->key]) == 0) {
			m_delete(phrases, p->key);
		}
	}
} // void deletePhrase()



/**
 * Сохраняет текст подсказки из prompts[] в базу.
 * @param key - ключ сообщения.
 * @param uid - ID оператора, поменявшего подсказку.
 */
void savePrompt(string key, int uid) {
	BotSkin skin = getCurrentSkin();
	Sql.Sql db = game->sqlConnect();
	sql_row_t row;
	string query;
	query = sprintf("delete from PROMPTS where name = '%s' and skin_id = %d and ovr <> 0", db->quote(key), skin->id);
	db->big_query(query);
	query = sprintf("insert into PROMPTS(name,value,skin_id,ovr,user_id) values('%s','%s',%d,1,%d)",
		db->quote(key), db->quote(getPrompt(key)), skin->id, uid);
	db->big_query(query);
} // void savePrompt()

/**
 * Удаляет подсказку из prompts[] и из базы.
 * @param key - ключ подсказки.
 */
void deletePrompt(string key) {
	Sql.Sql db = game->sqlConnect();
	string query = sprintf("delete from PROMPTS where name = '%s' and skin_id = %d", db->quote(key), getCurrentSkin()->id);
	db->big_query(query);
	m_delete(prompts, key);
} // void deletePrompt()


/**
 * Сохраняет параметры команды в базу.
 * @param cmd_name - название команды.
 */
void saveCommand(string cmd_name) {
	BotSkin skin = getCurrentSkin();
	Sql.Sql db = game->sqlConnect();
	Commands cmd = commands[cmd_name];
	int cid = cmd->id;
	string query;
	
	// Основные параметры.
	query = sprintf("update COMMANDS set cmdgroup = '%s', source = '%s' where id = %d", 
		db->quote(cmd->group), db->quote(cmd->source), cid);
	db->big_query(query);
	
	// Синонимы.
	query = sprintf("delete from COMMANDS_ALIASES where cmd_id = %d and skin_id = %d", cid, skin->id);
	db->big_query(query);
	foreach (cmd->synonimes, string syn) {
		query = sprintf("insert into COMMANDS_ALIASES(cmd_id, name, skin_id) values(%d, '%s', %d)", cid, db->quote(syn), skin->id);
		db->big_query(query);
	}
} // void saveCommand()

