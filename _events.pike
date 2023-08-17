//
// ### Функции-обработчики событий IRC
//

   string replyTo = "";
   
   void onLogin() {
      log(debug_log,"On login event");
      
      if ( irc->getNickInUse() ) {
         // Ник занят.
         // Просим никсерв освободить ник и ждем от него нотиса об освобождении.
         log(debug_log, "onLogin: bot's nick is in use, using ns ghost.");
         string nsGhost = sprintf("ns ghost %s %s", settings["nick"]->value, settings["nickservpassword"]->value);
         irc->raw(nsGhost);
         return;
      }

      if (login_text) {
         log(debug_log,"Performing autologin...");
         for (int i=0;i<sizeof(login_text);i++) {
            login_text[i]=replace(login_text[i],"$mynick",settings["nick"]->value);
            login_text[i]=replace(login_text[i],"$gamechannel",settings["gamechannel"]->value);
            irc->raw(login_text[i]);
         }
      }

      log(debug_log,sprintf("Joining [%s]...",settings["gamechannel"]->value));
      irc->join(settings["gamechannel"]->value);
      irc->message(settings["gamechannel"]->value,settings["color.regular"]->value,_about+" *** " + _version + " ***");
      irc->raw(sprintf("MODE %s %s",settings["gamechannel"]->value,settings["gameendchannelmode"]->value));
      log(debug_log,sprintf("Joining [%s]...",settings["talkschannel"]->value));
      irc->join(settings["talkschannel"]->value);

      game->loadBanList();

      if (settings["autostart"]->value=="on" && gameStatus==STOP) {
         game->setGameStatus(IDLE);
         game->startGame();
      }

   }

   void onDisconnect() {
      irc->connectionCounter = 0;
      
      // stop write thread and clear output buffer.
      remove_call_out(irc->writeTID);
      irc->outputLines = ({ });

      // Если это коннект после дисконнекта, игра начинается заново
      gameStatus = STOP; 
      mixed err = catch {
         game->stopAllTimers();
      };
      if (err) {
         logError(sprintf("onDisconnect: game->stopAllTimers() failed: %s", describe_backtrace(err)));
      }

      int reconnect_delay = irc->getReconnectDelay();
log(debug_log, sprintf("Reconnecting in %d seconds.", reconnect_delay));
      call_out(irc->connect, reconnect_delay, settings["server"]->value, settings["port"]->value);
   }

   void onJoin() {
log(debug_log,sprintf("   [onJoin:%s->%s]",msg->nick,msg->target+" mynick="+settings["nick"]->value));
      string nick = lower(msg->nick);

      if (lower(msg->target) == lower(settings["gamechannel"]->value)
         && "yes" == lower(settings["away_track"]->value)
         )
      {
         if (lower(msg->nick) != lower(settings["nick"]->value))
         {
            irc->raw("WHO " + msg->nick);
         }
      }

      if (lower(msg->target)==lower(settings["gamechannel"]->value)) dbLog(msg->target,"",sprintf(" * %s (%s) joined to %s",msg->nick,msg->address,msg->target));
      if (lower(msg->target)==lower(policeChannel)) dbLog("police.all","",sprintf(" * %s (%s) joined to %s",msg->nick,msg->address,msg->target));
      if (lower(msg->target)==lower(mafioziChannel)) dbLog("mafiozi.all","",sprintf(" * %s (%s) joined to %s",msg->nick,msg->address,msg->target));
      if (lower(msg->target)==lower(hooliganChannel)) dbLog("hooligan.all","",sprintf(" * %s (%s) joined to %s",msg->nick,msg->address,msg->target));

      // Кикаем заложника с канала офиса/логова/шайки хулигана.
      Player p = players[nick];
      if ( ! zero_type(p) && p->isHostage)
      {
         if (lower(msg->target) == lower(policeChannel))
         {
            irc->kick(msg->target, p->usernick, getMessage("policechannel_kick_reason"));
         }
         if (lower(msg->target) == lower(mafioziChannel))
         {
            irc->kick(msg->target, p->usernick, getMessage("mafiozichannel_kick_reason"));
         }
         if (lower(msg->target) == lower(hooliganChannel))
         {
            irc->kick(msg->target, p->usernick, getMessage("hooliganchannel_kick_reason"));
         }
      }

		if (nick != lower(settings["nick"]->value) && (zero_type(players[nick]) || players[nick]->alive < 10)) {
			if (lower(msg->target) == lower(policeChannel)) {
				irc->kick(msg->target, msg->nick, getMessage("policechannel_kick_reason"));
				return;
			} else if (lower(msg->target) == lower(mafioziChannel)) {
				irc->kick(msg->target, msg->nick, getMessage("mafiozichannel_kick_reason"));
				return;
			} else if (lower(msg->target) == lower(hooliganChannel)) {
				irc->kick(msg->target, msg->nick, getMessage("hooliganchannel_kick_reason"));
				return;
			}
		}

		if (lower(settings["gamechannel"]->value)==lower(msg->target)) {
			log(lower(msg->target)," * " + msg->nick + " joined to " + msg->target);

log(debug_log,sprintf("   size of userlist for (%s)=%d",msg->target,sizeof(users)));

			if (nick==lower(settings["nick"]->value)) {
				users = ([ ]);
				int timerInitChannel = call_out(irc->initChannelInfo,5,msg->target);
			} else {
				users[nick] = User();
				users[nick]->usernick = msg->nick;
				users[nick]->address = msg->address;
				game->updateRegisteredNickInfo(users[nick]);
//irc->message(msg->target,settings["color.regular"]->value,sprintf("onJoin: %s (%d)",msg->nick,sizeof(users)));

				if (game->registeredPlayer(nick)<1) {
					irc->message(msg->nick,settings["color.regular"]->value,getMessage("greeting_for_nonregistered_users"));
				}
			}

			if (players[nick] && players[nick]->alive==13 && players[nick]->userId!=0) {
				irc->message(users[nick]->usernick,settings["color.error"]->value,getMessage("you_must_identify_to_continue_playing"));
			}

			if (!(players[nick])) {
				switch (gameStatus) {
					case IDLE:
						irc->notice(msg->nick, settings["color.regular"]->value,
							getMessage("greeting_mayregister"));
						return;
					case STOP:
						irc->notice(msg->nick, settings["color.regular"]->value,
							getMessage("greeting_stopped"));
						return;
					case REGISTER:
						irc->notice(msg->nick, settings["color.regular"]->value,
							getMessage("greeting_register"));
						return;
				}
				irc->notice(msg->nick, settings["color.regular"]->value,
					getMessage("greeting_gamestarted"));
			}
		} // if (lower(settings["gamechannel"]->value)==lower(msg->target))
	} // void onJoin()

   void onPart(int ... param) {

log(debug_log,sprintf("onPart: %s (msg->target=%s) gamechannel=%s",lower(msg->nick),lower(msg->target),settings["gamechannel"]->value));

      if (sizeof(param)<1) {
         if (lower(msg->target)==lower(settings["gamechannel"]->value)) dbLog(msg->target,"",sprintf(" * %s (%s) parts %s",msg->nick,msg->address,msg->target));
         if (lower(msg->target)==lower(policeChannel)) dbLog("police.all","",sprintf(" * %s (%s) parts %s",msg->nick,msg->address,msg->target));
         if (lower(msg->target)==lower(mafioziChannel)) dbLog("mafiozi.all","",sprintf(" * %s (%s) parts %s",msg->nick,msg->address,msg->target));
         if (lower(msg->target)==lower(hooliganChannel)) dbLog("hooligan.all","",sprintf(" * %s (%s) parts %s",msg->nick,msg->address,msg->target));
      } else {
         if (users[lower(msg->nick)]) dbLog(settings["gamechannel"]->value,"",sprintf(" * Quits: %s (%s)",msg->nick,msg->address));
         if (players[lower(msg->nick)] && players[lower(msg->nick)]->invitedToOffice==1) dbLog("police.all","@QUIT",sprintf(" * Quits: %s (%s)",msg->nick,msg->address));
         if (players[lower(msg->nick)] && players[lower(msg->nick)]->invitedToLogovo==1) dbLog("mafiozi.all","@QUIT",sprintf(" * Quits: %s (%s)",msg->nick,msg->address));
         if (players[lower(msg->nick)] && players[lower(msg->nick)]->invitedToHooligan) dbLog("hooligan.all","@QUIT",sprintf(" * Quits: %s (%s)",msg->nick,msg->address));
      }

      if (lower(msg->target)!=lower(settings["gamechannel"]->value) && sizeof(param)<1) return;

//      if (lower(msg->target)!=lower(settings["gamechannel"]->value)) return;
      
      if (msg->action=="KICK") msg->nick = msg->targetnick;
      string nick = lower(msg->nick);

      if (players[nick] && players[nick]->alive==10) {
         if (gameStatus==REGISTER) game->unreg(nick);
         if (gameStatus!=STOP && gameStatus!=IDLE && gameStatus!=REGISTER) {
            game->setPlayerStatus(nick,13);
            // Автоматически добавляем вышедшего игрока в список замен.
            boolean auto_replace = "yes" == lower(settings["auto_replace_on_part"]->value);
            if (auto_replace && !players[nick]->wantsReplace) {
               players[nick]->wantsReplace = players[nick]->autoReplace = true;
            }
            irc->message(settings["gamechannel"]->value,settings["color.regular"]->value,getMessage("user_exit_during_game"),players[nick]->nick());
         }
      }

      if (users[nick]) {
//log(debug_log, sprintf("USERLIST: gonna m_delete(users, '%s')", nick));
         m_delete(users, nick);
      }
//      irc->message(settings["gamechannel"]->value,settings["color.regular"]->value,sprintf("onPart: %s (%d)",msg->nick,sizeof(users)));
      if (nick==lower(settings["nick"]->value)) {
         irc->join(settings["gamechannel"]->value);
      }
   }

   void onNick() {
      constant THIS_NAME = "onNick";
//log(debug_log,sprintf("nick1=[%s] nick2=[%s]",msg->nick,msg->args));
      string old_nick = msg->nick;
      string old_nick_lc = lower(old_nick);
      string new_nick = msg->args;
      string new_nick_lc = lower(new_nick);
log(debug_log, sprintf("%s: old_nick='%s', old_nick_lc='%s', new_nick='%s', new_nick_lc='%s', getAliasByIdentifiedNick(old_nick_lc)=%O", THIS_NAME, old_nick, old_nick_lc, new_nick, new_nick_lc, getAliasByIdentifiedNick(old_nick_lc)));

      // Бот поменял ник, скорее всего перед этим было ns ghost.
      if (irc->randomNick != "" && lower(irc->randomNick) == old_nick_lc) {
         onLogin();
         return;
      }
      

      dbLog(lower(settings["gamechannel"]->value),"",sprintf(" * %s is now known as %s",old_nick,new_nick));

      User u = users[old_nick_lc];
      if (!zero_type(u)) {
         if (players[old_nick_lc] && players[old_nick_lc]->alive == 10 && gameStatus == REGISTER) {
            game->unreg(old_nick_lc);
         }
         User new_user = users[old_nick_lc];
         new_user->usernick = new_nick;
         if (new_user->id != 0) {
            new_user->id = 0;
            new_user->identifiedNick = "";
            new_user->groupIDs = (< >);
            new_user->syncGroupIDsString();
            new_user->wantsReplace = false;
            new_user->notifyOnRegStart = false;
            irc->message(new_nick, settings["color.regular"]->value, getMessage("you_were_deidentified"));
         }
//log(debug_log, sprintf("USERLIST: gonna m_delete(users, '%s')", old_nick_lc));
         m_delete(users, old_nick_lc);
         users[new_nick_lc] = new_user;
         game->updateRegisteredNickInfo(new_user);
         new_user->authorizedAtNickServ = false;
         new_user->authorizedNickServID = 0;
      }

//      irc->message(settings["gamechannel"]->value,settings["color.regular"]->value,sprintf("onNick: %s -> %s (%d)",msg->nick,msg->args,sizeof(users)));
      if (players[old_nick_lc] && players[old_nick_lc]->alive == 10 && gameStatus != STOP && gameStatus != IDLE && gameStatus != REGISTER) {
         game->setPlayerStatus(old_nick_lc, 13);
         irc->message(settings["gamechannel"]->value, settings["color.regular"]->value,
            getMessage("change_nick_back"), players[old_nick_lc]->nick());
         irc->devoice(new_nick);
      }

      if (players[new_nick_lc] && gameStatus != STOP && gameStatus != IDLE && gameStatus != REGISTER && players[new_nick_lc]->alive == 13) {
         game->setPlayerStatus(new_nick_lc, 10);
         irc->message(settings["gamechannel"]->value, settings["color.regular"]->value,
            getMessage("user_comes_back"), players[new_nick_lc]->nick());
         irc->voice(new_nick);
      }
   }

   void onQuit() {
//      msg->target = connect->channel;
      onPart(1);
   }

   void onText(string source) {
      string nick = lower(msg->nick);

//log(debug_log,sprintf("search=%d, %s = %s",search(msg->args,settings["nsidentquery"]->value),nick,lower(settings["nickservnick"]->value)));
      
      // Нотис от никсерва.
      if (nick == lower(settings["nickservnick"]->value)) {
log(debug_log, sprintf("NICKSERV: msg->args=[%s]", msg->args));
         if ( irc->getNickInUse() ) {
            // Строка, которую шлёт никсерв, когда освобождает ник.
            string nsNickReleased = replace(settings["nsnickreleased"]->value, "$mynick", settings["nick"]->value);
            if (search(msg->args, nsNickReleased) > -1) {
               // Никсерв освободил ник.
log(debug_log, "NICKSERV: bot's nick is released by NickServ, logging in.");
               irc->setNickInUse(0);
               irc->doLogin(settings["nick"]->value);
            }
            return;
         }
         if (search(msg->args, settings["nsidentquery"]->value) > -1) {
            irc->message(settings["gamechannel"]->value, settings["color.regular"]->value,
               getMessage("nickserv_ident_query_received"));
            irc->message(settings["nickservnick"]->value, "",
               sprintf("identify %s", settings["nickservpassword"]->value));
            irc->message(settings["chanservnick"]->value, "", sprintf("op %s %s",
               settings["gamechannel"]->value, settings["nick"]->value));
         }
         return;
      } // if (nick == lower(settings["nickservnick"]->value))

      // Уведомление об идентификации на ник у никсерва.
      // Формат: "+r ник_в_IRC номер_в_базе_NickServ " без кавычек,
      // где "ник" - ник, на который юзер авторизовался у никсерва,
      // а "номер" - номер ника в базе никсерва (выводится в /ns info ник).
      string nickserv_notice_service = settings["nickserv_notice_service"]->value;
      if (nickserv_notice_service != "" && msg->from == lower(nickserv_notice_service))
      {
         if (lower(settings["auto_authorize_registered_nicks"]->value) != "yes")
         {
            return;
         }
         array(string) a = map(String.trim_whites(msg->args) / " " - ({""}), String.trim_whites);
         if (sizeof(a) != 3)
         {
log(debug_log, sprintf("WARNING: onText: unexpected string from nickserv_notice_service: expected [+|-]r <nick> <nick_id>, got: '%s'", msg->args));
            return;
         }
log(debug_log, sprintf("onText: a=%O", a));
         if ("+r" != a[0] && "-r" != a[0])
         {
log(debug_log, sprintf("WARNING: onText: unexpected param[0]: expected \"+r\" or \"-r\", got: '%s'", a[0]));
            return;
         }
         string id_nick = a[1], id_nick_lc = lower(id_nick);
         if (id_nick_lc == lower(settings["nick"]->value))
         {
log(debug_log, sprintf("onText: id_nick_lc (%s)== lower(settings[\"nick\"]->value) (%s)", id_nick_lc, lower(settings["nick"]->value)));
            return;
         }
         int id_nick_id = (int)a[2];
         User u = users[id_nick_lc];
log(debug_log, sprintf("onText: u=%O, u->id=%s", u, !zero_type(u) ? (string)u->id : "n/a"));
         if (zero_type(u))
         {
logError(sprintf("WARNING: onText: got +r notice, but user is not in user list: '%s'", id_nick_lc));
            users[id_nick_lc] = u = User();
            u->usernick = id_nick;
         }
         game->updateRegisteredNickInfo(u);
log(debug_log, sprintf("onText: u->registeredNick=%d (%s), u->registeredNickServID=%d, u->autoIdentify=%d (%s)", u->registeredNick, u->registeredNick ? "true" : "false", u->registeredNickServID, u->autoIdentify, u->autoIdentify ? "true" : "false"));

         // Идентифицировались на ник.
         if ("+r" == a[0])
         {
            u->authorizedAtNickServ = true;
            u->authorizedNickServID = id_nick_id;
            if (nicklistReady)
            {
               if (u->autoIdentify)
               {
                  game->autoLogonUser(u);
               }
            }
            else
            {
               game->nicks_authorized_at_nickserv[id_nick_lc] = u;
            }
            return;
         }

         // Сняли идентификацию на ник.
         if ("-r" == a[0])
         {
            u->authorizedAtNickServ = false;
            u->authorizedNickServID = 0;
            if ( ! nicklistReady)
            {
               m_delete(game->nicks_authorized_at_nickserv, id_nick_lc);
            }
            return;
         }

         return;
      } // Уведомление об идентификации на ник у никсерва.

      if (!users[nick]) return;

      if (sizeof(msg->args)<1) return;

//log(debug_log,sprintf("msg->target=%s",msg->target));

      string logLine = "";

      if (msg->args[0..6] == "ACTION") {
         logLine = sprintf(" * %s %s", msg->nick, msg->args[8..sizeof(msg->args) - 2]);
      } else {
         logLine = sprintf("<%s> %s", msg->nick, msg->args);
      }

      // ### Flood control
      if (source != "t") {
         foreach(indices(ignoreList), string n) {
            if (users[nick]->usernick == n || users[nick]->address == ignoreList[n]) {
               if ( ! userIsMemberOfGroup(nick, UGC_ADMINISTRATORS)) {
                  return;
               }
            }
         }
//log(debug_log,sprintf("%s still ignored",nick));

         if (search("pm", source) > -1) {
            if (time() - users[nick]->lastActivityTime <= (int)settings["floodtimeinterval"]->value) {
               users[nick]->floodCounter++;
            } else {
               users[nick]->floodCounter = 0;
            }
            users[nick]->lastActivityTime = time();
//log(debug_log,sprintf("flood control: nick=[%s] lastActivityTime=%d floodCounter=%d",nick,users[nick]->lastActivityTime,users[nick]->floodCounter));

            if (users[nick]->floodCounter >= (int)settings["floodmaxlines"]->value && !userIsMemberOfGroup(nick, UGC_ADMINISTRATORS)) {
               game->ignore("", users[nick]->usernick + " " + settings["floodignoretime"]->value + " "
                  + getMessage("player_was_ignored_for_flood"));
               return;
            }
         }
      }
      // #################################

      if (msg->target[0] != '#') {
         dbLog(msg->nick, msg->nick, msg->args);
         log(msg->nick, logLine);
      }

      if (lower(msg->target) == lower(settings["gamechannel"]->value)) {
         dbLog(msg->target, msg->nick, msg->args);
         log(msg->target,logLine);
      }

      if (lower(msg->target) == lower(policeChannel)) {
         dbLog("police.all", msg->nick, msg->args);
         log("police.all",logLine);
      }
      
      if (lower(msg->target) == lower(mafioziChannel)) {
         dbLog("mafiozi.all", msg->nick, msg->args);
         log("mafiozi.all",logLine);
      }

      if (lower(msg->target) == lower(hooliganChannel)) {
         dbLog("hooligan.all", msg->nick, msg->args);
         log("hooligan.all",logLine);
      }

		/**
		 * CTCP processing
		 */
		if (msg->args[0] == '\001' && msg->args[-1] == '\001' && search(msg->args, "\001ACTION ") != 0) {
			if (msg->action == "PRIVMSG") {
				onCTCPRequest();
			} else if (msg->action == "NOTICE") {
				onCTCPReply();
			}
			return;
		}
		
      if (users[nick] && users[nick]->operator && !userIsMemberOfGroup(nick, UGC_ADMINISTRATORS)
         && !(players[nick] && players[nick]->alive >= 10) && source == "p"
         && gameStatus != STOP && gameStatus != IDLE && gameStatus != REGISTER)
      {
         irc->message(settings["gamechannel"]->value,settings["color.regular"]->value,getMessage("please_keep_silence_during_game"),users[nick]->nick());
         irc->deop(settings["gamechannel"]->value,users[nick]->usernick);
      }

      string command = "";
      replyTo = msg->target[0] == '#' ? msg->target : msg->nick;

      string args = strip_colors(msg->args);
      if (args != "" && args[0] == '!') {
         int sp_idx = search(args, " ");
         string takenCommand = sp_idx > -1 
            ? lower_case(String.trim_whites(args[1..sp_idx - 1])) 
            : lower_case(String.trim_whites(args[1..]));

         // Проверка на ночные заказы
         if (players[nick] && players[nick]->alive == 10
               && gameStatus == NIGHT
               && search("mlcx", source) > -1
            )
         {
            string cmdName = getRoleCommandName(players[nick]->role, takenCommand);
            if (cmdName != "") {
               if (roles[players[nick]->role]->nick == nick
                     // Миры могут шпионить все сразу.
                     || players[nick]->role == ROLE_CITIZEN && cmdName == "spyZ"
                     // Мафы 4-го уровня могут ходить все сразу.
                     || players[nick]->role == ROLE_MAFIOSI && players[nick]->level >= 4
                     // Члены шайки могут ходить все сразу.
                     || players[nick]->role == ROLE_PUNK
                  )
               {
                  Roles.Commands roleCmd = roles[players[nick]->role]->commands[cmdName];
                  // Фраза заказа берется из msg->args, а не из args,
                  // чтобы сохранить цвета, указанные игроком.
                  string phrase = roleCmd->nickRequired == NR_NONE ? getComment(msg->args, 1) : getComment(msg->args, 2);
log(debug_log,sprintf("cmd=%s nickRequired=%s", cmdName, nickRequirementNames[roleCmd->nickRequired]));
                  string victim = roleCmd->nickRequired != NR_NONE && sizeof(getparams(args)) > 1 ? getparams(args)[1] : "";
                  game->storeNightCommand(nick, roleCmd->code, takenCommand, (int)roleCmd->level, victim, phrase);
                  return;
               }
            }
         } // Проверка на ночные заказы
         
         string cmdName = getCommandName(takenCommand);
         if (cmdName > "")
         {
            // У юзера нет прав на выполнение команды.
            if ( ! userCanExecuteCommand(nick, cmdName))
            {
               irc->notice(msg->nick, settings["color.error"]->value, 
                  getMessage("you_have_no_rights_to_use_command"), cmdName);
               return;
            }

            // Команда дана не там, где можно.
            if (search(commands[cmdName]->source, source) < 0)
            {
               irc->notice(msg->nick, settings["color.regular"]->value,
                  getMessage("command_sources") + " "
                     + commands[cmdName]->getSourceNames(), cmdName);
               return;
            }

            command = cmdName;
         }

         if (sizeof(command) > 0) {
            log(debug_log, sprintf("command - %s->%s: ![%s]", msg->nick, msg->target, command));
         }

         // Проверка на дневное голосование
         string candidate_nick = game->getNick(takenCommand);
         if (candidate_nick != "") {
            if (players[candidate_nick]->alive >= 10 && gameStatus == VOTE 
                  && players[nick] && players[nick]->alive >= 10 && source == "p"
               )
            {
               game->storeCandidateVote(nick, candidate_nick);
            }
            return;
         }

         if (command == "") {
            // Нет такой команды.
            irc->notice(msg->nick, settings["color.error"]->value, getMessage("no_such_command"));
            return;
         }
      } else {
         // Транслируем обычные разговоры в офисе/логове тому, кто прослушивает.
         string target_lc = lower(msg->target);
         mixed spyRole = roles[ROLE_HACKER];
         Player spyPlayer = players[spyRole->nick];
         if (!zero_type(spyPlayer) && spyPlayer->alive == 10 && spyRole->isSpying && spyRole->spySource == target_lc) {
            string target_name = "(n/a)";
            if (target_lc == lower(mafioziChannel)) {
               target_name = commandSources["l"];
            } else if (target_lc == lower(policeChannel)) {
               target_name = commandSources["c"];
            }
            string translatedAction = sprintf("%s: <<r>%s</r>> %s", target_name, roles[players[nick]->role]->name, msg->args);
            irc->message(spyPlayer->usernick, settings["color.regular"]->value, translatedAction);
         }
      } // if (msg->args[0] == '!')

      if (command == "") { return; }

      logCommand(msg->nick, command, getComment(msg->args, 1));

      if (command == "!night") {
         if (gameStatus == VOTE && players[nick] && players[nick]->alive >= 10) {
            game->storeCandidateVote(nick, "!night");
         }
         return;
      }

      if (command == "identify") {
         game->identifyUser(msg->nick, getComment(msg->args, 1));
         return;
      }

      if (command == "start") {
         if (gameStatus == STOP) game->start(nick);
         return;
      }

      if (command == "reg") {
         if (source == "m") {
            array keys = getparams(msg->args);
            if (sizeof(keys)<2) {
               irc->message(msg->nick,settings["color.regular"]->value,getMessage("reguser_password_syntax"));
               return;
            }
            game->regUser(msg->nick,keys[1],msg->address);
         } else {
            if (gameStatus==IDLE) game->startGame();
            if (gameStatus==REGISTER) game->registerPlayer(nick,msg->address);
         }
         return;
      }

      if (command == "yes") {
         if (zero_type(players[nick]) || players[nick]->alive != 10) return;

         if (source == "m") {
            if (gameStatus == ROLESETTING && players[nick]->waitingForAcceptRole) {
               // Игрок принял предложенную роль.
               game->acceptRole(nick, getComment(msg->args, 1));
            } else if (gameStatus >= DAY && gameStatus <= FINALCANDIDATESPEECH && players[nick]->waitingForAcceptGun) {
               // Мир принял предложенный пистолет.
               game->acceptGun(nick);
            } else if (gameStatus == NIGHT && players[nick]->role == ROLE_DEALER) {
               // Барыга принял заказ.
               if (players[nick]->skipsTurn) {
                  irc->message(players[nick]->usernick, settings["color.regular"]->value, getMessage("you_skip_you_turn_because_of_hooligan"));
                  return;
               } else if (players[nick]->isHostage) {
                  irc->message(players[nick]->usernick, settings["color.regular"]->value, getMessage("hostages_cant_act"));
                  return;
               } else {
                  game->acceptShopOrder(nick, getComment(msg->args, 1));
               }
            }
         } // if (source=="m")

         if (source == "p") {
            if (gameStatus == EXECUTEVOTE && nick != game->victim) {
               // Игрок проголосовал за казнь подсудимого.
               game->storeYesNoVote(nick, command);
            }
         } // if (source=="p")

         return;
      } // if (command == "yes")

      
      if (command == "no") {
         if (zero_type(players[nick]) || players[nick]->alive != 10) return;

         if (source == "m") {
            if (gameStatus == ROLESETTING && players[nick]->waitingForAcceptRole) {
               // Игрок отказался от предложенной роли.
               game->rejectRole(nick, getComment(msg->args, 1));
            } else if (gameStatus >= DAY && gameStatus <= FINALCANDIDATESPEECH && players[nick]->waitingForAcceptGun) {
               // Мир отказался от предложенного пистолета.
               game->rejectGun(nick);
            } else if (gameStatus == NIGHT && players[nick]->role == ROLE_DEALER) {
               // Барыга отклонил заказ.
               if (players[nick]->skipsTurn) {
                  irc->message(players[nick]->usernick, settings["color.regular"]->value, getMessage("you_skip_you_turn_because_of_hooligan"));
                  return;
               } else if (players[nick]->isHostage) {
                  irc->message(players[nick]->usernick, settings["color.regular"]->value, getMessage("hostages_cant_act"));
                  return;
               } else {
                  game->cancelShopOrder(nick, getComment(msg->args, 1));
               }
            }
         } // if (source=="m")

         if (source == "p") {
            if (gameStatus == EXECUTEVOTE && nick != game->victim) {
               // Игрок проголосовал против казни подсудимого.
               game->storeYesNoVote(nick, command);
            }
         } // if (source == "p")

         return;
      } // if (command == "no")


      if (command == "whoknows") {
         if (zero_type(players[nick]) || players[nick]->alive != 10) return;

         if (source == "p" && gameStatus == EXECUTEVOTE && nick != game->victim) {
            // Игрок воздержался от голосования на казни подсудимого.
            game->storeYesNoVote(nick, command);
         }

         return;
      } // if (command == "whoknows")


      if (command == "voice") {
         if (players[nick] && players[nick]->alive >= 10) {
            if (players[nick]->level < roles[players[nick]->role]->voiceLevel) {
               irc->notice(nick, settings["color.regular"]->value,
                  getMessage("you_have_no_level_to_use_voice"));
            } else {
               game->playerVoice(nick, msg->args);
            }
         } 
         return;
      }

      if (command == "team") {
         game->changeTeam(nick, getComment(msg->args, 1));
         return;
      }

      if (command == "addclone") {
         array keys = getparams(msg->args);
         if (sizeof(keys) < 2) {
            irc->message(replyTo, settings["color.regular"]->value, getMessage("addclone_password_syntax"));
            return;
         }
         game->addClone(msg->nick, keys[1], getComment(msg->args, 2));
         return;
      }

      if (command == "cancel") {
         game->cancelNightCommand(nick);
         return;
      }

      if (command == "delclone") {
         array keys = getparams(msg->args);
         if (sizeof(keys) < 2) {
            irc->message(replyTo, settings["color.regular"]->value, getMessage("delclone_password_syntax"));
            return;
         }
         game->delClone(msg->nick, keys[1]);
         return;
      }

      if (command == "listclones") {
         game->listClones();
         return;
      }

      if (command == "players") {
         if (gameStatus != STOP && gameStatus != IDLE) game->listPlayers(replyTo);
         return;
      }

      if (command == "unreg") {
         if (gameStatus == REGISTER) game->unreg(nick);
         return;
      }

      if (command == "levels") {
         if (gameStatus != STOP && gameStatus != IDLE && gameStatus != REGISTER && gameStatus != ROLESETTING) {
            game->showLevels(getComment(msg->args, 1));
         }
         return;
      }

      if (command == "money") {
         if (gameStatus != STOP && gameStatus != IDLE && gameStatus != REGISTER && gameStatus != ROLESETTING) {
            game->showMoney(nick);
         }
         return;
      }

      if (command == "role") {
         if (gameStatus != STOP && gameStatus != IDLE && gameStatus != REGISTER && gameStatus != ROLESETTING) {
            game->showRole(nick);
         }
         return;
      }

      if (command == "usersnum") {
         game->showNumberOfUsers();
         return;
      }

      if (command == "allies") {
         if (gameStatus != STOP && gameStatus != IDLE && gameStatus != REGISTER && gameStatus != ROLESETTING) {
            game->showAllies(nick, replyTo);
         }
         return;
      }

      if (command == "turns") {
         if (gameStatus == ROLESETTING) game->showNonConfirmedRoles();
         if (gameStatus == NIGHT) game->showTurnsLeft();
         return;
      }

      if (command == "sqlinfo") {
         game->sqlInfo();
         return;
      }

      if (command == "roles") {
         if (gameStatus != STOP && gameStatus != IDLE && gameStatus != REGISTER && gameStatus != ROLESETTING) {
            irc->message(replyTo, settings["color.regular"]->value, game->showRoles());
         }
         return;
      }

      if (command == "raw") {
         irc->raw(getComment(msg->args, 1));

         // Рассылаем админам уведомление о факте использования команды.
         if ("yes" == lower(settings["notify_admins_on_raw_usage"]->value))
         {
            string rec_id = "n/a";
            Sql.Sql db = game->sqlConnect();
            string query = sprintf("select id from COMMANDS_HISTORY"
               + " where nick = '%s' and command = '%s'"
               + " order by id desc limit 1"
               , db->quote(nick), db->quote(command));
            //rec_id = db->big_query(query)->fetch_row()[0];

            string nick_lc = lower(msg->nick);
            string msg = getMessage("user_used_raw_command_notice");
            foreach (indices(users), string n)
            {
               User u = users[n];
               if (n != nick_lc && u->id > 0 && userIsMemberOfGroup(n ,UGC_ADMINISTRATORS))
               {
                  irc->notice(u->usernick, settings["color.error"]->value,
                     msg, users[nick]->usernick, rec_id);
               }
            }
         } // Рассылаем админам уведомление о факте использования команды.

         return;
      }

      if (command == "killerorder") {
         game->storeOrderForKiller(nick, getComment(msg->args, 1));
         return;
      }

      if (command == "guardianorder") {
         game->storeOrderForGuardian(nick, getComment(msg->args, 1));
         return;
      }

      if (command == "endreg") {
         if (gameStatus != REGISTER) return;
         irc->message(settings["gamechannel"]->value, settings["color.regular"]->value,
            getMessage("registration_was_completed_by"), users[nick]->title2, users[nick]->nick());
         remove_call_out(game->timerReg);
         game->timerRegMinsLeft = 0;
         game->endRegistration();
         return;
      }

      if (command == "all") {
         if (players[nick] == 0) return;
         if (gameStatus == CANDIDATESPEECH && players[nick]->alive >= 10 && nick == game->victim) {
            remove_call_out(game->executeVoting);
            if (players[nick]->skippedAll > 0) { players[nick]->skippedAll--; }
            game->executeVoting();
         } else if (gameStatus == FINALCANDIDATESPEECH && players[nick]->alive >= 10 && nick == game->victim) {
            remove_call_out(game->timerCandidateSpeech);
            if (players[nick]->skippedAll > 0) { players[nick]->skippedAll--; }
            game->execute();
         }
         return;
      }

      if (command == "rolecodes") {
         game->showRoleCodes();
         return;
      }

      if (command == "initrole") {
         game->initRole(nick, String.trim_whites(getComment(msg->args, 1)));
         return;
      }

      if (command == "points") {
         game->showPointsKey(nick, getComment(msg->args, 1));
         return;
      }

      if (command == "say") {
         game->say(nick, msg->args);
         return;
      }

      if (command == "warn") {
         game->warn(nick, msg->args);
         return;
      }

      if (command == "ban") {
         game->ban(nick, msg->args);
         return;
      }

      if (command == "unban") {
         if (sizeof(getparams(msg->args)) == 1) {
            game->help(nick, command);
            return;
         }
         game->unban(nick, getComment(msg->args, 1));
         return;
      }

      if (command == "block") {
         game->block(nick, getComment(msg->args, 1));
         return;
      }

      if (command == "unblock") {
         game->deleteBlock(nick, getComment(msg->args, 1));
         return;
      }

      if (command == "playerinfo") {
         if (sizeof(getparams(msg->args)) == 1) {
            game->help(nick, command);
            return;
         }
         game->playerInfo(getComment(msg->args, 1));
         return;
      }

      if (command == "whois") {
         game->whois(getComment(msg->args, 1));
         return;
      }

      if (command == "ignore") {
         game->ignore(nick, getComment(msg->args, 1));
         return;
      }

      if (command == "unignore") {
         game->unignore(nick, getComment(msg->args, 1));
         return;
      }

      if (command == "listignores") {
         game->showIgnoreList();
         return;
      }

      if (command == "invite") {
         game->invite(nick, getComment(msg->args, 1));
         return;
      }

      if (command == "timer") {
         game->showTimer();
         return;
      }

      if (command == "listbans") {
         game->listBans();
         return;
      }

      if (command == "listblocks") {
         game->listBlocks();
         return;
      }

      if (command == "op") {
         game->op(msg->args);
         return;
      }

      if (command == "deop") {
         game->deop(msg->args);
         return;
      }

      if (command == "halfop") {
         game->halfop(msg->args);
         return;
      }

      if (command == "dehalfop") {
         game->dehalfop(msg->args);
         return;
      }

      if (command == "join") {
         game->join(msg->args);
         return;
      }

      if (command == "part") {
         game->part(msg->args);
         return;
      }

      if (command == "mystatus") {
         game->mystatus(nick);
         return;
      }

      if (command == "unblockme") {
         game->unblockme(nick);
         return;
      }

      if (command == "admins") {
         game->admins(getComment(msg->args, 1));
         return;
      }

      if (command == "gamestatus") {
         game->gamestatus();
         return;
      }

      if (command == "banner") {
         game->showBanner(replyTo);
         return;
      }

      if (command == "addme") {
         game->addMe(nick);
         return;
      }

      if (command == "delme") {
         game->delMe(nick);
         return;
      }

      if (command == "guests") {
         game->guests();
         return;
      }

      if (command == "clearguests") {
         game->clearGuests();
         return;
      }

      if (command == "setbanner") {
         game->setBanner(nick, getComment(msg->args, 1));
         return;
      }

      if (command == "getmoney") {
         game->getMoney(nick, getComment(msg->args, 1));
         return;
      }

      if (command == "transfer") {
         game->transferMoney(getComment(msg->args, 1));
         return;
      }

      if (command == "topmoney") {
         game->showTopMoney();
         return;
      }

      if (command == "won") {
         game->showWon(nick, getComment(msg->args, 1));
         return;
      }

      if (command == "toproles") {
         game->showTopRoles(getComment(msg->args, 1));
         return;
      }

      if (command == "top") {
         game->showTop();
         return;
      }

      if (command == "statgame") {
         game->showStatGame(getComment(msg->args, 1));
         return;
      }

      if (command == "version") {
         game->version();
         return;
      }

      if (command == "about") {
         game->about();
         return;
      }

      if (command == "userlist") {
         game->userlist();
         return;
      }

      if (command == "stop") {
         game->stop(nick);
         return;
      }

      if (command == "restart") {
         game->restart();
         return;
      }

      if (command == "exit") {
         game->exittodos();
         return;
      }

      if (command == "setkey") {
         if (sizeof(getparams(msg->args)) < 2) {
            game->help(nick, command);
            return;
         }

         string key = getparams(msg->args)[1];

         if (sizeof(getparams(msg->args)) == 2) {
            game->showConfigKey(nick, key);
            return;
         }
         
         string equal = getparams(msg->args)[2]; // :-)

         if (equal != "=" || sizeof(getparams(msg->args)) < 4) {
            game->help(nick, command);
            return;
         }

         string value = getComment(msg->args, 3); //getparams(msg->args)[3];
         game->setConfigKey(nick, key, value);

         return;
      }

      if (command == "setrole") {
         if (sizeof(getparams(msg->args)) == 1) {
            game->help(nick, command);
            return;
         }
         game->setRole(nick, msg->args);
         return;
      }

      if (command == "commandshistory") {
         if (sizeof(getparams(msg->args)) == 1) {
            game->help(nick, command);
            return;
         }
         game->commandsHistory(nick, getComment(msg->args, 1));
         return;
      }

      if (command == "help") {
         string topic = sizeof(getparams(msg->args)) < 2 ? "help" : getparams(msg->args)[1]; //lower(getparams(msg->args)[1]);
         if (sizeof(getparams(msg->args)) > 2) {
            game->help(nick, topic, getparams(msg->args)[2]);
         } else {
            game->help(nick, topic);
         }
         return;
      }

      if (command == "mypassword") {
         game->myPassword(msg->nick, getComment(msg->args, 1));
         return;
      }

      if (command == "mytitle1") {
         game->myTitle(msg->nick, getComment(msg->args, 1), TITLE1, msg->nick);
         return;
      }

      if (command == "mytitle2") {
         game->myTitle(msg->nick, getComment(msg->args, 1), TITLE2, msg->nick);
         return;
      }

      if (command == "mybirthday") {
         game->myBirthday(msg->nick, getComment(msg->args, 1));
         return;
      }

      if (command == "myemail") {
         game->myEmail(msg->nick, getComment(msg->args, 1));
         return;
      }

      if (command == "shop") {
         game->shop(nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "buy") {
         if (players[nick] && players[nick]->alive == 10) {
            game->buy(nick, getComment(msg->args, 1));
         }
         return;
      }
      
      if (command == "stuff") {
         if (players[nick] && players[nick]->alive == 10) {
            game->showPlayerInventory(nick, getComment(msg->args, 1));
         }
         return;
      }
      
      if (command == "setartifact") {
         if (sizeof(getparams(msg->args)) < 2) {
            game->help(nick, command);
            return;
         }
         game->setArtifact(nick, msg->args);
         return;
      }
      
      if (command == "orders") {
         if (players[nick] && players[nick]->alive == 10) game->showOrders(nick);
         return;
      }
      
      if (command == "cancelorder") {
         if (players[nick] && players[nick]->alive == 10) game->cancelShopOrder(nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "setpoints") {
         game->setPoints(nick, getComment(msg->args, 1));
         return;
      }

      if (command == "birthdays") {
         game->showBirthdays(replyTo, false);
         return;
      }

      if (command == "settopic") {
         game->setTopic(nick, getComment(msg->args, 1));
         return;
      }

      if (command == "inviteme") {
         game->inviteMe(nick);
         return;
      }
      
      if (command == "useremail") {
         game->setUserEmail(msg->nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "userpassword") {
         game->setUserPassword(msg->nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "userskippedall") {
         game->setUserSkippedAll(msg->nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "usertitle1") {
         game->setUserTitle(msg->nick, getComment(msg->args, 1), TITLE1);
         return;
      }
      
      if (command == "usertitle2") {
         game->setUserTitle(msg->nick, getComment(msg->args, 1), TITLE2);
         return;
      }
      
      if (command == "adduser") {
         game->addUser(msg->nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "usergroups") {
         game->assignUserGroups(msg->nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "usercommand") {
         game->assignUserCommandRights(msg->nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "rehash") {
         game->rehash(msg->nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "setcommand") {
         game->setCommand(msg->nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "setmessage") {
         game->setConfigMessage(msg->nick, getComment(msg->args, 1), false);
         return;
      }
      
      if (command == "addmessage") {
         game->setConfigMessage(msg->nick, getComment(msg->args, 1), true);
         return;
      }
      
      if (command == "delmessage") {
         game->deleteConfigMessage(msg->nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "setprompt") {
         game->setConfigPrompt(msg->nick, getComment(msg->args, 1), false);
         return;
      }
      
      if (command == "addprompt") {
         game->setConfigPrompt(msg->nick, getComment(msg->args, 1), true);
         return;
      }
      
      if (command == "delprompt") {
         game->deleteConfigPrompt(msg->nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "userinfo") {
         game->userInfo(getComment(msg->args, 1));
         return;
      }

      if (command == "whowas") {
         game->whoWas(getComment(msg->args, 1));
         return;
      }
      
      if (command == "whomwas") {
         game->whomWas(getComment(msg->args, 1));
         return;
      }
      
      if (command == "blockhost") {
         game->blockHost(msg->nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "unblockhost") {
         game->unblockHost(msg->nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "lasterror") {
         game->showLastError(msg->nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "errorlog") {
         game->errorLog(msg->nick, getComment(msg->args, 1));
         return;
      }
      
      //if (command == "testerror") { throw( ({ "test error", backtrace() }) ); }
      
      if (command == "localtime") {
         game->showLocalTime();
         return;
      }
      
      if (command == "time") {
         game->showGameTime(replyTo);
         return;
      }
      
      if (command == "replaces") {
         game->showReplaces(nick);
         return;
      }
      
      if (command == "replace") {
         game->doReplace(nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "unreplace") {
         game->doUnreplace(nick);
         return;
      }

      if (command == "listen") {
         game->startListen(nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "unlisten") {
         game->stopUnlisten(nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "addblockedhostsexception") {
         game->addBlockedHostsException(msg->nick, getComment(msg->args, 1));
         return;
      }

      if (command == "delblockedhostsexception") {
         game->deleteBlockedHostsException(getComment(msg->args, 1));
         return;
      }
      
      if (command == "listblockedhostsexceptions") {
         game->showBlockedHostsExceptions();
         return;
      }
      
      if (command == "myregnotify") {
         game->myRegNotify(msg->nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "listskins") {
         game->showSkins();
         return;
      }
      
      if (command == "setskin") {
         game->setSkin(nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "initartifact") {
         game->initArtifact(nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "initkey") {
         game->initConfigKey(nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "initmessage") {
         game->initConfigMessage(nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "initpieces") {
         game->initPieces(nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "initpoints") {
         game->initPoints(nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "initprompt") {
         game->initPrompt(nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "rolefeatures") {
         game->showRoleFeatures();
         return;
      }
      
      if (command == "addphrase") {
         game->addConfigPhrase(nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "setphrase") {
         game->setConfigPhrase(nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "delphrase") {
         game->deleteConfigPhrase(nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "initphrase") {
         game->initConfigPhrase(nick, getComment(msg->args, 1));
         return;
      }
      
      if (command == "skills") {
         game->showSkills(getComment(args, 1));
         return;
      }
      
      if (command == "groupcommand") {
         game->assignGroupCommandRights(nick, getComment(args, 1));
         return;
      }
      
      //if (command == "userkey") {
      //   game->assignUserConfigKeyRights(nick, getComment(args, 1));
      //   return;
      //}
      
      if (command == "groupkey") {
         game->assignGroupConfigKeyRights(nick, getComment(args, 1));
         return;
      }

      if (command == "redeem")
      {
         game->storeRedeemOffer(nick, getComment(args, 1));
         return;
      }

      if (command == "myautoid")
      {
         game->myAutoId(nick, getComment(args, 1));
         return;
      }

      if (command == "commandhistory")
      {
         game->commandHistory(nick, getComment(msg->args, 1));
         return;
      }

      // Команда применения артефакта?
      string artifactCode = getArtifactCode(command);
      if (!zero_type(artifacts[artifactCode])) {
         if (players[nick] && players[nick]->alive == 10) {
log(debug_log, sprintf("onText: artifact command: command='%s', msg->args='%s'\n", command, msg->args));
            game->onArtifactCommand(nick, command, getComment(msg->args, 1));
         }
         return;
      }

      // Обработчик команды не найден.
      logError(sprintf("ERROR: command handler not found: ![%s]", command));
      irc->message(replyTo, settings["color.error"]->value, getMessage("command_handler_not_found"), command);
   } // void onText()





   void parseModesLine() {
      string channel = "";
      if (search(msg->args,"MODE ")>=0) channel = msg->args[search(msg->args,"MODE ")+5..];
      if (search(channel," ")>=0) channel = channel[..search(channel," ")-1];
      string modes = msg->args[search(msg->args,channel)+sizeof(channel)+1..];
      channel = lower(channel);
//log(debug_log,sprintf("   channel=[%s] modes=%s",channel,modes));
      if (channel!=lower(settings["gamechannel"]->value)) return;


//log(debug_log,sprintf("   parseModesLine:nick=%s target=%s mode=%s",msg->nick,msg->target,modes));
//      string  modes = search(msg->args," ")>=0 ? msg->args[0..search(msg->args," ")-1] : msg->args;
      array targets = modes/" ";
      string  targets_string = modes[search(modes," ")..];
      modes = (modes/" ")[0];
      string  modeSign = "+";
      string  paramModeCounter = 0;
      string  param = "";
//log(debug_log,sprintf("   modes=%s targets=%O",msg->args,modes,targets));
      string  reverseLine = replace(modes,"-","?") + targets_string; reverseLine = replace(reverseLine,"+","-"); reverseLine = replace(reverseLine,"?","+");
      reverseLine = "MODE " + msg->target + " "  + reverseLine;
      if (msg->nick=="" || lower(msg->nick)==lower(settings["chanservnick"]->value) || msg->nick==settings["nick"]->value || users[lower(msg->nick)] && userIsMemberOfGroup(lower(msg->nick), UGC_ADMINISTRATORS))
         reverseLine = "";
//log(debug_log,sprintf("   REVERSE=[%s]",reverseLine));

      foreach (modes/"", string key) {
//log(debug_log,sprintf("   KEY=[%s]",key));
//         checkMode(msg->nick,msg->target,msg->args[key[0]]);
         if (key=="+" || key=="-") {
            modeSign = key;
         } else {
            if (msg->target[0]=='#' && search(irc->channelModesRequiredParameters,key)>=0) {
               param=(string)targets[paramModeCounter+1];
               paramModeCounter++;
            }
            onMode(msg->nick,msg->target,modeSign+key,param);
            param="";
         }
      }

//write(sprintf("   reverseLine=[%s]\n",reverseLine));
      if (sizeof(reverseLine)>0 && nicklistReady==1) irc->raw(reverseLine);
   
   
   
   }

   void onMode(string who, string target, string mode, mixed ... param) {
log(debug_log,sprintf("   onMode:nick=%s target=%s mode=%s [%s]",who,lower(target),mode,param[0]));
log(lower(target),who + " sets mode " + mode + " to " + param[0]);
//irc->message(settings["gamechannel"]->value,settings["color.system"]->value,sprintf("Wow! Catched %s %s to %s by %s!",mode,param[0],target,who));
      
      // server sets a channel/user mode.
      if ("" == msg->nick) {
         // PROBABLY, this is a net-join'ed server setting +mN/-mN on channel,
         // or +v/-v for a user.
         // invert modes set by such a server.
         if ("yes" == lower(settings["guardgamechannelmodesonnetjoin"]->value) 
               && lower(target) == lower(settings["gamechannel"]->value)
            )
         {
log(debug_log, sprintf("Inverting mode [%s] because it's set by a net-join'ed server (%s).", mode, msg->from));
            mode[0] = '+' == mode[0] ? '-' : '+';
            irc->raw(sprintf("MODE %s %s", target, mode));
            return;
         }
      }

      string nick = param[0], nick_lc = lower(nick);
      User u = users[nick_lc];
      if (zero_type(u)) return;

      if (mode == "-o") {
         if (lower(target) == lower(settings["gamechannel"]->value)) {

#if 0
            if (zero_type(u)) {
               u = users[nick_lc] = User();
               u->usernick = nick;
            }
#endif // 0

            if (u) {
               u->operator = false;
            }
            if (nick_lc == lower(settings["nick"]->value)) {
               irc->message(settings["gamechannel"]->value,
                  settings["color.system"]->value, getMessage("bot_must_be_op"));
               irc->message(settings["chanservnick"]->value, "",
                  sprintf("op %s %s", settings["gamechannel"]->value,
                     settings["nick"]->value)
                  );
            }
         }
      }

      if (mode == "+o") {
         if (lower(target) == lower(settings["gamechannel"]->value)) {
#if 0
            if (zero_type(u)) {
               u = users[nick_lc] = User();
               u->usernick = nick;
            }
#endif // 0

            if (u) {
               u->operator = true;
            }
            
            if (nick_lc == lower(settings["nick"]->value)) {
               if (topic != "") {
log(debug_log, sprintf("TOPIC: %s", topic));
                  irc->raw(sprintf("TOPIC %s :%s", settings["gamechannel"]->value, topic));
               }
            }
         }
      }

   
      if (mode == "-h" && lower(target) == lower(settings["gamechannel"]->value)) {
         if (u) {
            u->halfOp = false;
         }
      }

      if (mode == "+h" && lower(target) == lower(settings["gamechannel"]->value)) {
         if (u) {
            u->halfOp = true;
         }
      }

      if (mode == "-v" && lower(target) == lower(settings["gamechannel"]->value)) {
         if (u) {
            u->voice = false;
         }
      }

      if (mode == "+v" && lower(target) == lower(settings["gamechannel"]->value)) {
         if (u) {
            u->voice = true;
         }
      }

   } // void onMode()


	/**
	 * Обработчиков запросов CTCP.
	 */
	void onCTCPRequest() {
		string s = msg->args[1..sizeof(msg->args)-2];
		int sp_idx = search(s, " ");
		string req = sp_idx > -1 ? s[..sp_idx - 1] : s;
//log(debug_log, sprintf("CTCPREQUEST: s=%O, req=%O", s, req));
		switch (req) {
			case "PING":
				irc->ctcpReply(msg->nick, s);
				break;
			case "VERSION":
				irc->ctcpReply(msg->nick, sprintf("%s Mafion %s", req, _version));
				break;
			case "TIME":
				irc->ctcpReply(msg->nick, sprintf("%s %s", req, 
					replace(ctime(mktime(localtime(time() ) ) ), (["\n":""]) ) ) );
				break;
		} // switch (req)
	} // void onCTCPRequest()
	
	/**
	 * Обработчик ответов CTCP.
	 */
	void onCTCPReply() {
	} // void onCTCPReply()
