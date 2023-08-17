// Модуль IRC

#include "_LineBreaker.pike"

class Irc {
   
//   string server    = settings["server"]->value;
//   int    port    = settings["port"]->value;
//   string mynick    = settings["mynick"]->value;
//   string ident   = settings["ident"]->value;
//   string realname  = settings["realname"]->value;
//   string connectCode = settings["connectcode"]->value;

//   int    maxTriesNumber  = settings["maxtriesnumber"]->value;
//   int    connectionDelay = settings["connectiondelay"]->value;

   int nickInUse = 0; // ник занят?
   string randomNick = ""; // рандомный ник на случай занятого.
   
   boolean throttled = false; // получен отлуп из-за слишком большого кол-во коннектов за маленькое время

   int    connectionCounter = 0;
   int    connectionTimer = 0;

   string outputBuffer = "";
   string inputBuffer = "";
   
   // next socket write time.
   int nextSendTime = 0; 
   // write thread run interval, in seconds.
   float writeInterval = 0.5;
   // write call-out id.
   mixed writeTID = UNDEFINED; 
   // IRC command end-of-line sequence.
   constant EOL = "\r\n";
   // line breaker for output buffer.
   LineBreaker lbw = LineBreaker(EOL);
   // output lines.
   array(string) outputLines = ({ });

   string channelModesRequiredParameters = "ohvbekl";

   Stdio.File Socket    = Stdio.File();

   int connect(string server, string port) {
      connState=S_CONNECTING;
      Socket->open_socket();
      Socket->set_blocking();

      int res=0;
      irc->connectionCounter++;

      log(debug_log,sprintf("Connecting to %s/%u (%u)...",server,(int)port,irc->connectionCounter));
      res=Socket->connect(server,(int)port);

      if (res!=1) {
         int delay = getReconnectDelay();
         int en = Socket->errno();
         log(debug_log, sprintf("Error connecting to %s/%u (%u)! (next try in %d secs): %d (%s)", server,
            (int)port, irc->connectionCounter, delay, en, strerror(en)));
         if ((int)settings["maxtriesnumber"]->value > 0 && irc->connectionCounter>=(int)settings["maxtriesnumber"]->value) {
            log(debug_log,sprintf("Maximum connections number exceed! Exit!"));
            exit(0);
         }

         connectionTimer = call_out(connect, delay, server, port);
         return 0;
      }
      
      setThrottled(false);

      Socket->set_nonblocking();
      Socket->set_read_callback(read_callback);
      Socket->set_write_callback(write_callback);
      Socket->set_close_callback(close_callback);

      log(debug_log,sprintf("Registering on the server as %s/%s (%s)...",
      settings["nick"]->value,
      settings["ident"]->value,
      settings["realname"]->value));
      connState=S_REGISTER;
      raw(sprintf("USER %s hostname servername :%s", settings["ident"]->value,settings["realname"]->value));
      raw(sprintf("NICK %s", settings["nick"]->value));
      return 1;
   }

   void read_callback_OLD(mixed id, string data) {
//      log(debug_log,sprintf("READ CALLBACK (%u-%O)",gameStatus,(string)s));
      int   lf=0, start=0;
      string line;
      lf=0; start=0;
      while ((lf=search(data,"\n", lf+1))>=0) {
         if ( parseLine(data[start..lf-2]) ) {
            processMessage();
         }
//log(debug_log,sprintf("[%s]",data[start..lf-2]));
         start=lf+1;
      }
   }
   
  void read_callback(mixed id, string data) {
    array(string) lines = data / "\r\n";
//log(debug_log, sprintf("READ: data=[%s], lines=%O", data, lines));
    if (inputBuffer != "") {
      lines[0] = inputBuffer + lines[0];
      inputBuffer = "";
    }
    if (data[sizeof(data) - 2..] != "\r\n") {
      inputBuffer = lines[-1];
      lines = lines[..sizeof(lines) - 1];
    }
    foreach (lines, string line) {
      if (line == "") { continue; }
      if ( parseLine(line) ) {
        processMessage();
      }
    }
  }


//void raw(string text) { buff += text + "\r\n"; write_callback(); }
//void write_callback() { while (sizeof(buff) && (n = Socket->write(buff)) > 0) buff = buff[n..]; }
   
   void write_callback_OLD() {
//      log(debug_log,"WRITE CALLBACK");
      int n = 0;
      while (sizeof(irc->outputBuffer) && (n = Socket->write(irc->outputBuffer)))
         irc->outputBuffer = irc->outputBuffer[n..];
   }
   
   void write_callback_no_delay() {
      constant THIS_NAME = "write_callback_no_delay";
//log(debug_log, sprintf("%s", THIS_NAME));
      while (sizeof(outputLines) > 0) {
         string line = outputLines[0];
         int len = strlen(line);
         int sent = Socket->write(line);
         if (sent < 1) {
int en = Socket->errno();
log(debug_log, sprintf("Socket write error: %d: %s", en, strerror(en)) );
            break;
         }
         if (sent == len) {
            outputLines = outputLines[1..];
         } else {
            // Only part of line has been written.
            // Saving remainder of sent line for a
            // next round.
            outputLines[0] = line[sent..];
            break;
         }
      }
   }
   

   void write_callback() {
      constant THIS_NAME = "write_callback";
      
      // no delay during logon.
      if (S_CONNECTING == connState || S_REGISTER == connState) {
//log(debug_log, sprintf("%s: Logging on server, not delaying.", THIS_NAME));
         write_callback_no_delay();
         //writeTID = call_out(write_callback, writeInterval);
         return;
      }
      
      int irc_cmd_delay_delim = settings["irc_command_delay_delimiter"]
         ? (int)settings["irc_command_delay_delimiter"]->value : 0;
      // no delay.
      if (irc_cmd_delay_delim < 1) {
//log(debug_log, sprintf("%s: irc_command_delay_delimiter < 1, not delaying.", THIS_NAME));
         write_callback_no_delay();
         //writeTID = call_out(write_callback, writeInterval);
         return;
      }
      // nothing to output.
      if (sizeof(outputLines) < 1) {
         //writeTID = call_out(write_callback, writeInterval);
         return;
      }

      int t = time();
      int diff = nextSendTime - t;
      if (0 == nextSendTime || diff <= 0) {
         string line = outputLines[0];
         int len = strlen(line);
         if (len > 1) {
//log(debug_log, sprintf("%s: t=%d, nextSendTime=%d, diff=%d.", THIS_NAME, t, nextSendTime, diff));
//log(debug_log, sprintf("<< %s\n", line));
            int sent = Socket->write(line);
//log(debug_log, sprintf("%s: len=%d, sent=%d.", THIS_NAME, len, sent));
            if (sent == len) {
               outputLines = outputLines[1..];
            } else {
               // Only part of line has been written.
               // Saving remainder of sent line for a
               // next round.
               outputLines[0] = line[sent..];
            }
            if (sizeof(outputLines) > 0) {
               if (0 == nextSendTime || diff < 0) {
                  nextSendTime = t;
               }
               nextSendTime += 1 + (sent / irc_cmd_delay_delim);
            } else {
               nextSendTime = 0;
            }
//log(debug_log, sprintf("%s: nextSendTime=%d", THIS_NAME, nextSendTime));
         }
      }

      writeTID = call_out(write_callback, writeInterval);
   }

   void close_callback() {
//      log(debug_log,"CLOSE CALLBACK");
      onDisconnect();
   }

   void raw(string text) {
//      log(debug_log,"Sending: ["+text+"]");
//      Socket->write(text+"\r\n");
      irc->outputBuffer += text + "\r\n";
//log("incoming.log","->"+text);
      array(string) a = lbw->split(text + "\r\n", true);
//log(debug_log, sprintf("Irc::raw: a=%O\n", a));
      outputLines += a;
//log(debug_log, sprintf("Irc::raw: outputLines=%O\n", outputLines));
      write_callback(); //Socket->write(""); //
   }

   /**
    * Парсит строку, принятую от IRC сервера и заполняет
    * глобальную переменную msg.
    * @return true - строка распарсена, и сообщение требует
    * дальнейшей обработки, false - строка НЕ распарсена
    * и/или сообщение НЕ требует дальнейшей обработки.
    */
   boolean parseLine(string line) {
//      write(sprintf("   parse: [%s]\n",line));

      if (lower(settings["incominglog"]->value) == "on") {
         log("!incoming.log",line);
      }

//      Stdio.File file=Stdio.File("logs/"+debug_log, "caw");
//      int now=time();
//      file->write(sprintf("%u %s\n",now,line));
//      file->close();

      int sp = 0, prevsp, colon, colonCheck, cnt = 0;
      array(string) token = ({ });
      array(string) n = ({ });
      msg = Msg();

      line = String.trim_whites(line);

// Next line was added 2005-02-03
      if (line == "") { return false; }

      if (line[0] == ':') {
         if (search(line, " ") < 0) {
            // Broken?
            return false;
         }
         line = line[1..];
      } else {
         //token += ({ "" }); cnt = 1;
         // Unreal3.2.1-DalNetRU2.0 шлет некоторые ответы на /WHO (код ответа - 352)
         // БЕЗ префикса (имени сервера), т.е. ответ начинается с кода 352.
         // Или это был косяк в парсере? 0:-)
         line = "[NO_ORIGINATOR] " + line;
      }
//log(debug_log,sprintf("line 1=[%O]",line));

      colon=search(line, ":",1);
      if (colon<0) { colonCheck=sizeof(line); } else { colonCheck=colon; }
      do {
         sp=search(line, " ",sp+1);
         if (sp<0) { sp=sizeof(line); }
         token+=({line[prevsp..sp-1]});
         prevsp = sp+1;
         if (cnt==2) msg->args = line[sp+1..];
         cnt++;
      } while (sp>=0 && sp<colonCheck);

//log(debug_log,sprintf("-------------------- token start=[%s]",token[1]));
      if (token[cnt-1][0]==':') { token[cnt-1]=token[cnt-1][1..]; }
//log(debug_log,sprintf("->line 2=[%O]",line));
//log(debug_log,sprintf("->colon=[%d]",colon));
//log(debug_log, sprintf("Irc::parseLine: token=%O", token));

      sp=search(token[0],"!");
      msg->nick = token[0][..sp-1];
      msg->address = token[0][search(token[0],"@")+1..];
      msg->from = token[0];
      if (sizeof(token)>1) msg->action = token[1];
      if (sizeof(token)>2) msg->target = token[2];
      if (sizeof(token)>3) msg->targetnick = token[3];
      
      if (colon >= 0 || msg->action == "PART" || msg->action == "MODE") {
         if (msg->action != "352") {
            msg->args = line[colon + 1..];
         }
      } else {
         return false;
      }

//log(debug_log,sprintf("size of token=%d",sizeof(token)));
//if (sizeof(token)>1) log(debug_log,sprintf("token %d=[%s]",sizeof(token),token[1]));

//log(debug_log,sprintf("msg->nick=[%s] msg->address=[%s] msg->from=[%s] msg->action=[%s] msg->args=[%s]",msg->nick,msg->address,msg->from,msg->action,msg->args));
      return true;
   } // boolean parseLine()

   /**
    * Обрабатывает пришедшее сообщение от сервера.
    */
   void processMessage() {
      if (msg->action == "ERROR") {
         logError(sprintf("ERROR: IRC server error: %s", msg->args));
         if (search(msg->args, settings["throttled_message"]->value) > -1) {
log(debug_log, "THROTTLED!");
            setThrottled(true);
         }
         onDisconnect();
         return;
      }

      if (msg->action == "PING") {
         irc->raw(sprintf("PONG :%s", msg->args));
         return;
      }

      if (msg->action == settings["connectcode"]->value) {
         connState = S_CONNECTED;
         onLogin(); //onConnect();
         return;
      }

//log(debug_log,sprintf("line 3=[%O]",line));
//log(debug_log,sprintf("msg->args=[%O]",msg->args));
/*
      if (sizeof(msg->args)>2 && msg->args[0]=='' && msg->args[sizeof(msg->args)-1]=='' && msg->args[0..6]!="ACTION") {
         msg->args = msg->args[1..sizeof(msg->args)-2];
// debug it
//         onCTCP();
         return;
      }
*/
//log(debug_log,sprintf("msg->action=[%s] line=[%s]",msg->action,line));
//2005-02-07 23:13:27 :irc.itslan.ru 315 MafionFish #mafion :End of /WHO list.

      switch (msg->action) {
         //case "NOTICE": onText("m"); break;
         case "JOIN": onJoin(); break;
         case "NOTICE":
         case "PRIVMSG":
            if (lower(msg->target)==lower(settings["gamechannel"]->value)) onText("p");
            if (lower(msg->target)==lower(settings["talkschannel"]->value)) onText("t");
            if (lower(msg->target)==lower(policeChannel)) onText("c");
            if (lower(msg->target)==lower(mafioziChannel)) onText("l");
            if (lower(msg->target)==lower(hooliganChannel)) onText("x");
            if (msg->target[0] != '#') onText("m");
            break;
         case "MODE":  parseModesLine(); break;
         case "PART":  onPart();   break;
         case "QUIT":  onQuit();   break;
         case "KICK":  onPart();   break;
         case "NICK":  onNick();   break;
         case "352":
            // line=server.dal.net.ru 352 Mafion #mafion ~mafion localhost.wplus.net server.dal.net.ru Mafion H*@ :0 Бот для игры в мафию, (c) Wolf The White 2003-2005
            // msg->args=#mafion ~mafion localhost.wplus.net server.dal.net.ru Mafion H*@ :0 Бот для игры в мафию, (c) Wolf The White 2003-2005
            // keys[0] - название канала.
            // keys[1] - username.
            // keys[2] - адрес.
            // keys[3] - сервер.
            // keys[4] - ник.
            // keys[5] - моды.
            // keys[6] - хопы.
            // keys[7..] - realname.
            array(string) keys = msg->args / " "; //line / " ";
//log(debug_log, sprintf("352: msg->args=%O, keys=%O", msg->args, keys));
            string username = keys[1];
            string addr = keys[2];
            string nick = keys[4];
            string nick_lc = lower(nick);
            string modes = keys[5];
//log(debug_log, sprintf("352: username=%O, addr=%O, nick=%O, modes=%O", username, addr, nick, modes));

//log(debug_log,sprintf("352 nick=%s",nick));
            
            User u = users[nick_lc] || User();
            u->usernick = nick;
            u->address = addr;
            u->ident = username;
            u->operator = search(modes, "@") > -1;
            u->voice = search(modes, "+") > -1;
            u->halfOp = search(modes, "%") > -1;
            u->isAway = search(modes, "G") > -1; // "H" - here, "G" - gone (away).
            users[nick_lc] = u;
            if ( ! nicklistReady)
            {
               game->updateRegisteredNickInfo(u);
            }
            break;

         case "315":
         {
            // line=:irc.network.name 315 zalldone #mafion :End of /WHO list.
            // msg->targetnick=#mafion
//log(debug_log, sprintf("Irc::processMessage: msg->action='%s', msg->target='%s', msg->targetnick='%s', msg->args='%s'", msg->action, msg->target, msg->targetnick, msg->args));
            if (lower(msg->targetnick) != lower(settings["gamechannel"]->value))
            {
log(debug_log, sprintf("Irc::processMessage: not game channel: %s", msg->targetnick));
               break;
            }
            if ( ! nicklistReady)
            {
               nicklistReady = true;
               message(settings["gamechannel"]->value,settings["color.system"]->value,getMessage("end_of_who"));
               game->autoId();
               if (game->startAfterNicklistReady) { game->startGame(); }
            }
            break;
         } // case "315"

         case "433":
            // nick already in use
            setNickInUse(true);
            randomNick = settings["nick"]->value;
            // append random digits after bot's nick.
            for (int i = random(6) + 3; i-- > 0; ) {
               randomNick += String.int2char(random(10) + 48); 
            }
logError(sprintf("433 nick in use, using random nick: '%s'", randomNick));
            raw(sprintf("NICK %s", randomNick));
            break;

      } // switch (msg->action)
   } // void processMessage()

   void join(string channel) {
      if (channel[0]!='#') channel='#'+channel;
      raw(sprintf("JOIN %s\r\n",channel));
   }

   void part(string channel, string reason) {
      if (channel[0]!='#') channel='#'+channel;
      raw(sprintf("PART %s :%s\r\n",channel,reason));
   }

   void invite(string nick, string channel) {
      raw(sprintf("INVITE %s :%s\r\n",nick,channel));
   }

   void initChannelInfo(string channel) {
log(debug_log,sprintf("irc->initChannelInfo(): initializing channel %s (/who)",channel));
      irc->raw("WHO "+channel);
      users = ([ ]);
   }

   void voice(string nick) {
      raw(sprintf("MODE %s +v %s\r\n",settings["gamechannel"]->value,nick));
   }

   void devoice(string nick) {
      raw(sprintf("MODE %s -v %s\r\n",settings["gamechannel"]->value,nick));
   }

   void ban(string channel,string address) {
      raw(sprintf("MODE %s +b %s\r\n",channel,address));
   }

   void unban(string channel,string address) {
      raw(sprintf("MODE %s -b %s\r\n",channel,address));
   }

   void op(string channel,string nick) {
      raw(sprintf("MODE %s +o %s\r\n",channel,nick));
   }

   void deop(string channel,string nick) {
      raw(sprintf("MODE %s -o %s\r\n",channel,nick));
   }

   void halfop(string channel,string nick) {
      raw(sprintf("MODE %s +h %s\r\n",channel,nick));
   }

   void dehalfop(string channel,string nick) {
      raw(sprintf("MODE %s -h %s\r\n",channel,nick));
   }

   void kick(string channel,string nick, string reason) {
      raw(sprintf("KICK %s %s :%s\r\n",channel,nick,reason));
   }

   void message(string target, string color, string text, mixed ... args) {
      if (users[target]) target = users[target]->usernick;
      sendline(target, "M", color, text, args);
   }

   void delayed_message(int delay, string devoicedNick, string target, string color, string text, mixed ... args) {
//      timerDelayForMessage = call_out(processDelayedMessage,delay,target,devoicedNick,color, text, args);
   }

   void processDelayedMessage(string target, string devoicedNick, string color, string text, mixed args) {
      sendline(target, "M", color, text, args);
      if (devoicedNick!="") devoice(devoicedNick);
   }

   void notice(string target, string color, string text, mixed ... args) {
      sendline(target, "N", color, text, args);
   }
   
  void ctcpRequest(string target, string text) {
    ctcp("M", target, text);
  }

  void ctcpReply(string target, string text) {
    ctcp("N", target, text);
  }
  
  void ctcp(string type, string target, string text) {
    if (text == "") { return; }
    if ('\001' != text[0]) { text = "\001" + text + "\001"; }
    sendline(target, type, "", text, ({ }));
  }

   void sendline(string target, string type, string color, string text, mixed args) {
      string linePrefix;
      switch (type) {
         case "M": linePrefix = "PRIVMSG %s :%s"; break;
         case "N": linePrefix = "NOTICE %s :%s"; break;
      }

//log(debug_log,sprintf("text=%O args=%O",text,args));
      text = parseMessage(color, text);
//log(debug_log,sprintf("text=%O args=%O",text,args));

      string t = sprintf(text,
         // Обязательно конвертим все дополнительные аргументы в строки,
         // т.к. в форматной строке text ожидаются только строки (%s).
         @map(args, lambda(mixed x){return (string)x;})
         );
      if (t == "") { return; }

      if (lower(target)!=lower(policeChannel) && lower(target)!=lower(mafioziChannel))
         dbLog(target,settings["nick"]->value,color+t);

      if (lower(target)==lower(policeChannel)) {
         dbLog("police.all",settings["nick"]->value,color+t);
      }

      if (lower(target)==lower(mafioziChannel)) {
         dbLog("mafiozi.all",settings["nick"]->value,color+t);
      }
      if (lower(target)==lower(hooliganChannel)) {
         dbLog("hooligan.all",settings["nick"]->value,color+t);
      }

      t = replace(t, (["\n":"<LF>", "\r":"<CR>"]));
/*
      int i = 0;
      while (i>=0) {
         i = search(t," ",i+1);
         if (i>400) {
            raw(String.trim_whites(sprintf(linePrefix,target,color+t[..i])));
            t = t[i..];
            i=0;
         }
      }
      raw(String.trim_whites(sprintf(linePrefix,target,color+t)));
*/
      int max_line_length = 400;
    array(string) a = word_wrap(t, max_line_length);
    foreach (a, string s) {
      raw(String.trim_whites(sprintf(linePrefix, target, color + s)));
    }
   }


   string parseMessage(string color, string message) {
//write(sprintf("MESSAGE=[%O]\n",message));

	   // Заменяем "%" на "%%" для sprintf().
	   message = replace(message, "%", "%%");

      message=replace(message,"$NICK",settings["color.nick"]->value+"%s"+color);
      message=replace(message,"$NUMBER",settings["color.number"]->value+"%s"+color);
      message=replace(message,"$ROLE",settings["color.role"]->value+"%s"+color);
      message=replace(message,"$NORMAL","%s");
      message=replace(message,"$PHRASE",settings["color.phrase"]->value+"%s"+color);

      message=replace(message,"<r>",settings["color.role"]->value);   message=replace(message,"</r>",color);
      message=replace(message,"<n>",settings["color.nick"]->value);   message=replace(message,"</n>",color);
      message=replace(message,"<number>",settings["color.number"]->value);  message=replace(message,"</number>",color);
      message=replace(message,"<bold>",settings["bold"]->value);    message=replace(message,"</bold>",settings["bold"]->value);
      message=replace(message,"<u>",settings["underline"]->value);    message=replace(message,"</u>",settings["underline"]->value);
      message=replace(message,"<night>",settings["color.night"]->value);    message=replace(message,"</night>",color);
      message=replace(message,"<system>",settings["color.system"]->value);  message=replace(message,"</system>",color);
      message=replace(message,"<day>",settings["color.day"]->value);    message=replace(message,"</day>",color);
      if (!zero_type(players[game->who]) && search(message,"$ORDERNICK")>=0) message=replace(message,"$ORDERNICK",settings["color.nick"]->value+players[game->who]->nick()+color);
      if (!zero_type(players[game->victim]) && search(message,"$VICTIM")>=0) message=replace(message, "$VICTIM", settings["color.nick"]->value + players[game->victim]->nick() + color);
      if (!zero_type(players[game->killPlayer]) && search(message,"$KILLEDPLAYER")>=0) message=replace(message,"$KILLEDPLAYER",settings["color.nick"]->value+players[game->killPlayer]->nick()+color);

      if (players[roles[ROLE_ATTORNEY]->nick]
            && players[roles[ROLE_ATTORNEY]->nick]->orderCommand == "substituteA"
            && search(message, "$SUBSTITUTEDNICK") >= 0
         )
      {
         message = replace(message, "$SUBSTITUTEDNICK", settings["color.nick"]->value
            + players[players[roles[ROLE_ATTORNEY]->nick]->orderNick]->nick() + color);
      }

      message = replace(message, (["&lt;": "<", "&gt;": ">"]));
      return message;
   }


   void setNickInUse(boolean bInUse) {
      nickInUse = bInUse;
   }
   
   boolean getNickInUse() {
      return nickInUse;
   }

   void doLogin(string nick) {
      if ( !getNickInUse() ) {
         raw(sprintf("USER %s hostname servername :%s", settings["ident"]->value, settings["realname"]->value));
      }
      raw(sprintf("NICK %s", nick));
   }
   
   boolean getThrottled() {
      return throttled;
   }
   
   void setThrottled(boolean isThrottled) {
      throttled = isThrottled;
   }

   /**
    * Возвращает интервал между попытками соединиться с IRC сервером.
    * @return интервал между попытками соединиться с IRC сервером.
    */   
   int getReconnectDelay() {
      int connect_delay = (int)settings["connectiondelay"]->value;
      if (!getThrottled()) { return connect_delay; }
      return max(connect_delay, (int)settings["throttled_reconnect_delay"]->value);
   }
}

Irc irc = Irc();

enum ConnectionState {
   S_IDLE,
   S_CONNECTING,
   S_CONNECTED,
   S_REPLY_WAIT,
   S_REGISTER,
   S_DISCONNECTED,
   S_DISCONNECTING,
};

ConnectionState connState;

