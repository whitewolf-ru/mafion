#! /usr/local/bin/pike

#define boolean int(0..1)
#define false 0
#define true (!false)

constant DATE_FORMAT = "%d-%m-%Y";
constant TIME_FORMAT = "%H:%i";
constant TIMESTAMP_FORMAT = DATE_FORMAT + " " + TIME_FORMAT; //"%d-%m-%Y %H:%i";

string _version = "v<number>0.15</number> 2009-01-13 лето";
string _about   = "<night>Mafion</night> - бот для игры в мафию."
   " (с) Wolf The White <number>2003</number>-<number>2009</number>"
   " | Адаптировано для IRCLine.RU <u><n>http://djkr.ru/mafion/</n></u>"
   " | Фразы - <n>Koimorn</n>, <n>Demiurg</n>, <n>wild</n>, <n>Binary</n>,"
      " <n>Евген</n>, <n>Рассвет</n>, <n>Aceler</n>"
   " | Для получения помощи напишите <night>!help</night> в приват боту"
   ;

array     login_text  = ({ });


mapping(string:string) messages = ([ ]);
mapping(string:string) prompts = ([ ]);
mapping(string:array(Phrase)) phrases = ([ ]);
mapping(string:int) points = ([ ]);

string debug_log = "debug.log";
int nicklistReady = 0;

string policeChannel = "";
string mafioziChannel = "";
string hooliganChannel = "";
int gameId = 0;

mapping(string:string) ignoreList = ([ ]);
mapping(string:string) commandGroups = ([ ]);


string banner = "";
string topic = "";

#include "_strip_colors.pike";
#include "_acl.pike";
#include "_classes.pike";
#include "_roles.pike";
#include "_configs.pike";
#include "_events.pike";
#include "_irc.pike";
#include "_game.pike";
#include "_functions.pike";
#include "_configs_export.pike";
#include "_skins.pike";

boolean exportMode = false;

int main(int argc, array(string) argv) {

   write(sprintf("---\n"));
   write(sprintf("--- IRC Mafia Game Bot - copyright (c) Wolf The White 2003-2009\n"));
   write(sprintf("--- Written for irc.ircnet.ru | Comments, wishes, treats? mafion@ircnet.ru\n"));
   write(sprintf("---\n\n"));
   
//   Locale.Gettext.setlocale(Locale.Gettext.LC_ALL, "windows-1251");

   exportMode = argc > 1 && (argv[1] == "-export" || argv[1] == "-e");
   loadConfiguration();

// Смена рута на пользователя, заданного в конфиге.
#if constant(getpwnam)
  string username = (string)settings["systemusername"]->value;
  array(int|string) ue = getpwnam(username);
  int my_uid = System.getuid();
  string my_username = getpwuid(my_uid)[0];
  // у рута uid - 0.
  if (my_uid == 0) {
    write("Changing user from %s to %s\n", my_username, username);
    int uid = (int)ue[2]; // User's ID
    int gid = (int)ue[3]; // User's primary group ID
    int en;
    en = System.setgid(gid);
    if (en != 0) {
      write("setgid(%d) failed: errno=%d (%s)\n", gid, en, strerror(en));
      exit(en);
    }
    en = System.setuid(uid);
    if (en != 0) {
      write("setuid(%d) failed: errno=%d (%s)\n", uid, en, strerror(en));
      exit(en);
    }
  } else if ( lower_case(my_username) != lower_case(username) ) {
    write("WARNING: current user (%s) is neither root, nor that specified in config (%s)\n", my_username, username);
  }
#endif

   loadLogin("bot.login");
   loadRoles(); //"roles.cfg"); loadRoles("roles.ovr");
   loadCommands(); //"commands.cfg");
   loadMessages(); //"messages.txt");
   loadPhrases(); //"phrases.txt");
   loadLevels(); //"levels.cfg");
   loadPrompts(); //"prompts.txt");
   loadPoints(); //"points.txt"); loadPoints("points.ovr");
   loadPieces(); //"pieces.cfg");
   loadArtifacts();
   if (!exportMode) { loadUserGroups(); }

   if (exportMode) { loadBannerFile(); }

   if (exportMode) {
      exportConfigs(argv[2..]);
      exit(0);
   }
   
   if (settings["skin"]->value != settings["default_skin"]->value) {
      write("Changing skin to %s...\n", settings["skin"]->value);
      setCurrentSkin(settings["skin"]->value);
   }

   game->loadIgnoreList();

   if (!exportMode) {
      game->loadBlockedHosts();
      game->loadBlockedHostsExceptions();
      game->loadClones();
   }

//   read_bad_words();

   if (!exportMode) { loadBanner(); }
   game->timerEveryMinuteTimer = call_out(game->everyMinuteTimer,60);
   if ((int)settings["bannershowtimeinterval"]->value>60)
      game->showBannerTimer = call_out(game->timerShowBanner,(int)settings["bannershowtimeinterval"]->value);

   loadTopic();

   // Таймер поздравления именинников.
   int interval = settings["showbirthdaysinterval"] ? (int)settings["showbirthdaysinterval"]->value : 0;
   int interval_s = interval * 60 * 60;
   if (interval_s > 0) {
      game->showBirthdaysTimer = call_out(game->timerShowBirthdays, interval_s);
   }

   write(sprintf("\n"));

   gameStatus = STOP;

#if constant(fork)
   if (settings["backgroundmode"]->value == "on") {
      if (fork() != 0) {
         // Родитель.
         exit(0);
      } else {
         // Ребенок.
         // Отцепляемся от консоли.
         Stdio.stdin.close();
         Stdio.stdout.close(); Stdio.stdout.open("/dev/null", "w");
         Stdio.stderr.close(); Stdio.stderr.open("/dev/null", "w");
      }
   }
#endif

   random_seed(time()|(getpid()<<8));

   log(debug_log,sprintf("START (%s)",_version));

   if (irc->connect(settings["server"]->value,settings["port"]->value)==3) {
      write("---Error connecting to server!");
      return 0;
   }

   while(1) {
      mixed err = catch {
         while(1) _static_modules.Builtin.__backend(3600.0);
      };
      logError(sprintf("Error:\n%s", describe_backtrace(err)));
      irc->message(settings["gamechannel"]->value,settings["color.system"]->value,getMessage("error"));
      irc->message(settings["gamechannel"]->value,settings["color.system"]->value,describe_backtrace(err)[0..100] + " ...");
   }

   exit(0);

}
