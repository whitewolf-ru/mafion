// data for string pieces() function.
mapping(string:array(string)) pieces_map = ([ ]);

array (string) getparams (string line, mixed ... args) {

   line=String.trim_whites(line);

   string separator = sizeof(args)>0 ? args[0] : " ";

   array (string) words = ({ });
   int i = 0;
   int start = 0;

   line = replace(line,"	","");

   while (i<=sizeof(line)) {

      while (i<sizeof(line) && line[i..i]!=separator) i++;
      words += ({ line[start..i-1] });

      while (i<sizeof(line) && line[i..i]==separator) i++;
      start = i;

      i++;

   }
   return words;
}

void log(string filename, string s) {
   mapping time = localtime(time());
//sprintf("%*.*s", width, maxwidth, str)
   string str;
   if (filename==debug_log) {
      str = sprintf("%s %s\n",
                           sprintf("%04u-%02u-%02u %02u:%02u:%02u %*.*s",
                              time->year+1900,
                              time->mon+1,
                              time->mday,
                              time->hour,
                              time->min,
                              time->sec,
                           7,7,
                              game->getGameStatus(gameStatus)
                           )
                           ,s
                );
   } else {
      str = sprintf("%s %s\n",
                           sprintf("%04u-%02u-%02u %02u:%02u:%02u",
                              time->year+1900,
                              time->mon+1,
                              time->mday,
                              time->hour,
                              time->min,
                              time->sec
                           )
                           ,s
                );
   }

   if (settings["debug"]->value == "on") {
#ifdef __NT__
      filename = replace(filename, ([ "\\":"_", "/":"_", ":":"_", "*":"_", "?":"_", "\"":"_", "<":"_",
         ">":"_", "|":"_" ]) );
#endif
      if (!Stdio.is_dir("logs")) { mkdir("logs"); }
      Stdio.File file = Stdio.File("logs/" + filename, "caw");
      file->write(str);
      file->close();
   }
   if (settings["debug"]->value == "on" && filename == debug_log) write(str);
//return;

   // ### post line to SQL table
   if (filename == debug_log) {
      Mysql.mysql_result sqlResult;
      object dbLocal = game->sqlConnect();
      string query = sprintf("insert into DEBUGLOG set TIMESTAMP = '%s', GAMESTATUS = '%s', GAMEID = %d, LINE = '%s';", dbLocal->quote(str), dbLocal->quote(game->getTextGameStatus(gameStatus)), gameId, dbLocal->quote(s));
      sqlResult = dbLocal->big_query(query);
   }

}

string lower(string text) {
   for (int i=0;i<sizeof(text);i++) {
      switch (text[i]) {
         case 'A': text[i]='a'; break;
         case 'B': text[i]='b'; break;
         case 'C': text[i]='c'; break;
         case 'D': text[i]='d'; break;
         case 'E': text[i]='e'; break;
         case 'F': text[i]='f'; break;
         case 'G': text[i]='g'; break;
         case 'H': text[i]='h'; break;
         case 'I': text[i]='i'; break;
         case 'J': text[i]='j'; break;
         case 'K': text[i]='k'; break;
         case 'L': text[i]='l'; break;
         case 'M': text[i]='m'; break;
         case 'N': text[i]='n'; break;
         case 'O': text[i]='o'; break;
         case 'P': text[i]='p'; break;
         case 'Q': text[i]='q'; break;
         case 'R': text[i]='r'; break;
         case 'S': text[i]='s'; break;
         case 'T': text[i]='t'; break;
         case 'U': text[i]='u'; break;
         case 'V': text[i]='v'; break;
         case 'W': text[i]='w'; break;
         case 'X': text[i]='x'; break;
         case 'Y': text[i]='y'; break;
         case 'Z': text[i]='z'; break;
         case 'А': text[i]='а'; break;
         case 'Б': text[i]='б'; break;
         case 'В': text[i]='в'; break;
         case 'Г': text[i]='г'; break;
         case 'Д': text[i]='д'; break;
         case 'Е': text[i]='е'; break;
         case 'Ё': text[i]='ё'; break;
         case 'Ж': text[i]='ж'; break;
         case 'З': text[i]='з'; break;
         case 'И': text[i]='и'; break;
         case 'Й': text[i]='й'; break;
         case 'К': text[i]='к'; break;
         case 'Л': text[i]='л'; break;
         case 'М': text[i]='м'; break;
         case 'Н': text[i]='н'; break;
         case 'О': text[i]='о'; break;
         case 'П': text[i]='п'; break;
         case 'Р': text[i]='р'; break;
         case 'С': text[i]='с'; break;
         case 'Т': text[i]='т'; break;
         case 'У': text[i]='у'; break;
         case 'Ф': text[i]='ф'; break;
         case 'Х': text[i]='х'; break;
         case 'Ц': text[i]='ц'; break;
         case 'Ч': text[i]='ч'; break;
         case 'Ш': text[i]='ш'; break;
         case 'Щ': text[i]='щ'; break;
         case 'Ъ': text[i]='ъ'; break;
         case 'Ы': text[i]='ы'; break;
         case 'Ь': text[i]='ь'; break;
         case 'Э': text[i]='э'; break;
         case 'Ю': text[i]='ю'; break;
         case 'Я': text[i]='я'; break;
      }
   }
   return text;
}

string pieces(int n, string kind) {
   string s;
   string ns = (string)n;

   switch (ns[sizeof(ns)-1]) {
      case '0': s=pieces_map[kind][2]; break;
      case '1': s=pieces_map[kind][0]; break;
      case '2': s=pieces_map[kind][1]; break;
      case '3': s=pieces_map[kind][1]; break;
      case '4': s=pieces_map[kind][1]; break;
      case '5': s=pieces_map[kind][2]; break;
      case '6': s=pieces_map[kind][2]; break;
      case '7': s=pieces_map[kind][2]; break;
      case '8': s=pieces_map[kind][2]; break;
      case '9': s=pieces_map[kind][2]; break;
   }
   if (n>=11 && n<=14) { s=pieces_map[kind][2]; }

   return (string)s;
}

string getComment(string s, int wordNo) {
   s = String.trim_whites(s);
   s = replace(s,"	","");
   if (sizeof(s)<1) return "";
   int  n = 0;
   int  i = 0;
   while (n<wordNo) {
      while (i<sizeof(s) && s[i]!=' ') i++;
      while (i<sizeof(s) && s[i]==' ') i++;
      n++;
   }
   return String.trim_whites(s[i..]);
}

array a_delete(array List, string nick) {
   array tmpArray=({});
   int Pos=search(List,nick);
   for (int i=0;i<sizeof(List);i++) {
      if (i!=Pos) { tmpArray+=({List[i]}); }
   }
   return tmpArray;
}

string getRandomString(int n) {
   string s = "";
   for (int i=1;i<=n;i++) {
      s += sprintf("%c",random(26)+65);
   }
   return s;
}

int gettime(string line) {
   string number = "";
   int secs = 0;
write(sprintf("line=[%s]\n",line));
   for (int i=0;i<sizeof(line);i++) {
      if ((int)line[i]>=48 && (int)line[i]<=57) {
         number += line[i..i];
      } else {
         switch ((string)line[i..i]) {
            case "s": secs += (int)number;      break;
            case "m": secs += (int)number*60;     break;
            case "h": secs += (int)number*60*60;    break;
            case "D": secs += (int)number*60*60*24;   break;
            case "M": secs += (int)number*60*60*24*30;    break;
            case "Y": secs += (int)number*60*60*24*30*365;  break;
         }
         number = "";
      }
   }
//write(sprintf("secs=[%d]\n",secs));
   return secs;
}

string phrase(string key) {
   if (!phrases[key] || sizeof(phrases[key])==0) return sprintf("<system>Забыли написать фразу для ключа <r>%s</r></system>!",key);
   return (random(phrases[key]))->text;
}

Phrase getPhraseByID(int id) {
	foreach (indices(phrases), string key) {
		foreach (phrases[key], Phrase p) {
			if (p->id == id) { return p; }
		}
	}
	return UNDEFINED;
}

void logCommand(string nick, string command, string param) {
//return;
   object db  = game->sqlConnect();
   string query;
   mapping time = localtime(time());
   string str = 
                        sprintf("%04u%02u%02u%02u%02u%02u",
                           time->year+1900,
                           time->mon+1,
                           time->mday,
                           time->hour,
                           time->min,
                           time->sec
                        );
   // Названия команд, параметры которых не надо писать в базу.
   // Обычно, это команды, связанные с паролем юзера.
   array(string) hide_params_commands = ({ "identify", "reg", "mypassword" });
   if (search(hide_params_commands, command) > -1)
   {
      param = "N/A";
   }
   query = sprintf("insert into COMMANDS_HISTORY set TIMESTAMP = '%s', GAME_ID = %d, NICK = '%s', COMMAND = '%s', PARAMS = '%s';", 
      db->quote(str), gameId, db->quote(nick), db->quote(command), db->quote(param));
//log(debug_log,"logCommand: query=@"+query+"@");
   game->sqlResult = db->big_query(query);
}

string prepareStatement(string s) {
//   s = replace(s,"'","\'");
//   s = Sql.sql_util.quote(s);
//log(debug_log,s);
   return s;
}

void postLog(string who, string action, string victim) {
   return; // решили, что stat.csv больше не нужен.
   mapping time = localtime(time());
   string str =  sprintf("%04u%02u%02u%02u%02u%02u", time->year+1900, time->mon+1, time->mday, time->hour, time->min, time->sec);
   if (!Stdio.is_dir("logs")) { mkdir("logs"); }
   Stdio.File file=Stdio.File("logs/stat.csv", "caw");
   string role = players[who] ? players[who]->role : "";
   file->write(sprintf("%s,%d,%s,%s,%s,%s,%s\n",str,gameId,game->getGameStatus(gameStatus),who,role,action,victim));
   file->close();
}

void dbLog(string filename, string from, string s) {
//return;
   Mysql.mysql_result   sqlResult;
   mapping time = localtime(time());

   string str = sprintf("%s %s\n",sprintf("%04u-%02u-%02u %02u:%02u:%02u %*.*s",time->year+1900,time->mon+1,time->mday,time->hour,time->min,time->sec,7,7,game->getGameStatus(gameStatus)),s);

   object dbLocal = game->sqlConnect();
//log(debug_log,sprintf("filename=%s from=%s s=%s",filename,from,s));

   string query = 
   sprintf(
   "insert into IRCLOGS set GAMESTATUS = %d, GAMEID = %d, OBJECT = '%s', MSG_FROM = '%s', LINE = '%s';",
   gameStatus,
   gameId,
   dbLocal->quote(filename),
   dbLocal->quote(from),
   dbLocal->quote(s)
   );
   sqlResult = dbLocal->big_query(query);

   // ### post line to SQL table
   if (filename == debug_log) {
      object  dbLocal = game->sqlConnect();
      query = sprintf("insert into DEBUGLOG set TIMESTAMP = '%s', GAMESTATUS = '%s', GAMEID = %d, LINE = '%s';", dbLocal->quote(str), dbLocal->quote(game->getTextGameStatus(gameStatus)), gameId, dbLocal->quote(s));
      sqlResult = dbLocal->big_query(query);
   }

}

/**
 * Объединяет элементы массива в строку.
 * @param a - массив.
 * @param separator - строка-разделитель элементов.
 * @return строку, содержащую элементы массива, разделенные строкой-разделителем. :)
 */
string a_join(array a, string separator) {
   string s = "";
   foreach (a, mixed v) {
      s += (s > "" ? separator : "") + (string)v;
   }
   return s;
}

/**
 * Объединяет элементы хэша (mapping) в строку.
 * @param m - хэш.
 * @param args[0] - строка-разделитель элементов.
 * @param args[1] - строка-разделитель пары ключ-значение.
 * По умолчанию используется ":".
 */
string m_join(mapping m, mixed ... args) {
   int argc = sizeof(args);
   string elmSeparator = argc > 0 ? args[0] : ",";
   string pairSeparator = argc > 1 ? args[1] : ":";
   string s = "";
   foreach (indices(m), mixed key) {
      s += (s > "" ? elmSeparator : "") + sprintf("%s%s%s", (string)key, pairSeparator, (string)m[key]);
   }
   return s;
}


/**
 * Возвращает полный код артефакта по синониму.
 * Если синоним совпадает с полным кодом, то просто вернет этот синоним.
 * @param synonym - полный код или синоним артефакта.
 * @return Полный код артефакта, или пустую строку, если ничего не найдено.
 */
string getArtifactCode(string synonym) {
   if (artifacts[synonym]) return synonym;
   foreach (indices(artifacts), string code) {
      if (search(artifacts[code]->synonyms, synonym) > -1) return code;
   }
   return "";
}


/**
 * Возвращает код команды роли (killC, checkH и т.п.) по синониму.
 * @param roleCode - код роли, среди команд которой искать.
 * @param syn - синоним команды. Также это может быть
 * основное название команды.
 * @return код команды или пустую строку, если ничего не найдено.
 */
string getRoleCommandName(string roleCode, string syn) {
//log(debug_log, sprintf("getRoleCommandName: roleCode='%s', syn='%s'", roleCode, syn));
   //syn = lower(syn);
   Roles role = roles[roleCode];
   foreach (indices(role->commands), string cmdName) {
      if (cmdName == syn) { return cmdName; }
		if (role->commands[cmdName]->name == syn) { return cmdName; }
      if (search(role->commands[cmdName]->synonimes, syn) > -1) { return cmdName; }
   }
   return "";
} // string getRoleCommandName()


/**
 * Возвращает название команды бота (НЕ роли) по синониму.
 * @param syn - синоним команды. Также это может быть
 * основное название команды - в таком случае оно же и будет
 * возвращено.
 * @return основное название команды или пустую строку,
 * если ничего не найдено.
 */
string getCommandName(string syn) {
   //syn = lower(syn);
   if (!zero_type(commands[syn])) { return syn; }
   foreach (indices(commands), string cmdName) {
      if (search(commands[cmdName]->synonimes, syn) > -1) { return cmdName; }
   }
   return "";
} // string getCommandName()


/**
 * Возвращает текст сообщения из messages.txt.
 * @param code - код (ключ) сообщения.
 * @return текст сообщения или предупреждение, если сообщение не найдено.
 */
string getMessage(string key) {
	string msg = messages[key];
	if (zero_type(msg)) {
		msg = sprintf("<system>Забыли написать сообщение для ключа <r>%s</r></system>!", key);
		log(debug_log, sprintf("ERROR: getMessage(): key not found: '%s'. backtrace: %s", key, 
			describe_backtrace(backtrace())));
	}
	return msg;
}

/**
 * Возвращает текст подсказки ролям из prompts[].
 * @param code - код (ключ) сообщения.
 * @return текст сообщения или предупреждение, если сообщение не найдено.
 */
string getPrompt(string key) {
	string msg = prompts[key];
	if (zero_type(msg)) {
		msg = sprintf("<system>Забыли написать подсказку для ключа <r>%s</r></system>!", key);
		log(debug_log, sprintf("ERROR: getPrompt(): key not found: '%s'. backtrace: %s", key, 
			describe_backtrace(backtrace())));
	}
	return msg;
}


/**
 * Возвращает ник юзера на канале, идентифицировавшегося на ник в базе.
 * @param nick - ник в базе.
 * @return ник юзера на канале пустую строку, если на ник никто не
 * идентифицировался.
 */
string getAliasByIdentifiedNick(string nick) {
   nick = lower(nick);
   foreach (indices(users), string n) {
	   if (lower(users[n]->identifiedNick) == nick) return n;
	}
	return "";
}

string getAlias(string nick) {
   nick = lower(nick);
   foreach (indices(users), string n) {
	   if (n == nick || lower(users[n]->identifiedNick) == nick) return n;
	}
	return "";
}


/**
 * Сохраняет сообщение об ошибке в базу.
 * @param msg - сообщение об ошибке.
 */
void logError(string msg) {
	mixed err = catch {
		log(debug_log, msg);
		Sql.Sql db = game->sqlConnect();
		string query = sprintf("insert into ERROR_LOG(message) values('%s')", db->quote(msg));
		db->big_query(query);
	};
	if (err) {
		// the only thing can be done is to ignore error. :(
		write("PANIC: can't log error: %s\n=====\n%s\n=====\n", msg, describe_backtrace(err));
	}
}

/**
 * Разбивает строку по словам на массив строк, длиной не превышающих длину строки.
 * @param s - строка.
 * @param line_length - длина строки.
 * @return массив строк.
 */
array(string) word_wrap(string s, int line_length) {
	int len = strlen(s);
	if (len <= line_length) { return ({ s }); }
	array(string) a = ({ });
	for (int i = 0; i < len; i+= line_length) {
		int end_idx = i + line_length;
		// Последний кусок строки.
		if (end_idx >= len) {
			a += ({ s[i..] });
			break;
		}
		string t = s[i..end_idx - 1];
		string tr = reverse(t);
		int sp_idx = search(tr, " ");
		if (sp_idx < 0) {
			a += ({ t });
		} else {
			a += ({ t[..line_length - sp_idx - 1] });
			i -= sp_idx;
		}
	}
	return a;
}
