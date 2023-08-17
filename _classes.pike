#include "_artifacts.pike"

/**
 * Коды ролей.
 * Предпочтительнее использовать эти константы в коде
 * вместо строк в чистом виде.
 */
constant ROLE_ANY         = "*";
constant ROLE_ATTORNEY    = "A";
constant ROLE_HOMELESS    = "B";
constant ROLE_CATTANI     = "C";
constant ROLE_DOCTOR      = "D";
constant ROLE_MAFIOSI     = "F";
constant ROLE_GUARDIAN    = "G";
constant ROLE_HACKER      = "H";
constant ROLE_DEALER      = "I";
constant ROLE_KILLER      = "K";
constant ROLE_MANIAC      = "M";
constant ROLE_PUNK        = "P";
constant ROLE_REPORTER    = "R";
constant ROLE_SLUT        = "S";
constant ROLE_TERRORIST   = "T";
constant ROLE_HOOLIGAN    = "X";
constant ROLE_CITIZEN     = "Z";


/**
 * Коды команд (team).
 * Предпочтительнее использовать эти константы в коде
 * вместо строк в чистом виде.
 *
 * Определены для единообразия, чтобы не было путаницы
 * при определении классов ролей в _roles.pike, типа:
 * team = ROLE_*; // вроде команда, но почему РОЛЬ_*?
 *
 * Нейтралы играют сами за себя, поэтому у каждого нейтрала
 * своя команда. Исключая завербованных игроков, конечно.
 */
constant TEAM_CITIZEN     = ROLE_CITIZEN;
constant TEAM_MAFIOSI     = ROLE_MAFIOSI;
constant TEAM_DEALER      = ROLE_DEALER;
constant TEAM_GUARDIAN    = ROLE_GUARDIAN;
constant TEAM_HACKER      = ROLE_HACKER;
constant TEAM_KILLER      = ROLE_KILLER;
constant TEAM_MANIAC      = ROLE_MANIAC;
constant TEAM_SLUT        = ROLE_SLUT;
constant TEAM_TERRORIST   = ROLE_TERRORIST;
constant TEAM_HOOLIGAN    = ROLE_HOOLIGAN;
 
class Settings {
	inherit ACLCacheContainer;

	string name;
	int    level;
	string value;
	
	// название, заданное в конфиге (с учетом регистра).
	string originalKey;
	
	// Оверрайдит дефолтное значение?
	boolean isOvr;
	
	// Оверрайдит дефолтное описание?
	boolean isDescOvr;
	
	// ID в базе.
	// Если равно нулю, значит ключ загружен НЕ из базы, а из файла.
	int id = 0;

	static void create() {
		ACLCacheContainer::create( ({ "ACL_WRITE_KEY", "ACL_ASSIGN" }) );
	}

}


mapping(string:Settings)  settings  = ([ ]);



class Msg {
	string from;
	string nick;
	string address;
	string action;
	string target;
	string targetnick;
	string args;
}



class User {
	int id = 0; // ID юзера в базе

	// в какие группы входит юзер.
	// Если захочется поменять руками, то не забываем вызвать syncGroupIDsString().
	multiset(int) groupIDs = (< userGroups[UGC_GUESTS]->id >);

	// разделённый запятыми список ID групп.
	// используется в SQL-запросе при проверке прав на выполнение команд.
	string gids_string = "";

	// Ник, на который идентифицировался юзер: !id ник пароль.
	string identifiedNick = "";

	string usernick  = "";
	string ident   = "";
	//UserLevel status = UL_GUEST;
	string address   = "";
	int    operator  = 0;
	int    halfOp    = 0;
	int    voice   = 0;
	boolean isAway = false;

	int    money   = 0;
	string offeredRoles  = ""; // для отказа от роли

	string title1    = "";
	string title2    = "";

	int    regsSkipped = 0; // количество пропущенных регистраций
	int    skippedAll  = 0;
	int    blockedTill = 0;

	int    lastActivityTime= 0; // для контроля флуда
	int    floodCounter  = 0; // счётчик строк для контроля флуда
	int    floodCtrlStartTime= 0; // время, когда был включён игнор пользователя

	// хочет ли юзер заменить собой игрока.
	boolean wantsReplace = false;
	
	// Уведомлять в приват о начале регистрации?
	boolean notifyOnRegStart = false;

	// Неограниченное число отказов от ролей?
	boolean unlimitedRoleRejects = false;
	
	// Права доступа. Те, которые в таблице RIGHTS находятся.
	int accessRights = 0;

	// Авторизован ли у никсерва (+r).
	boolean authorizedAtNickServ = false;

	// ID ника в базе никсерва, на который авторизовался юзер.
	int authorizedNickServID = 0;

	// Зарегистрирован ли ник в базе.
	// Используется для автоидентификации у бота
	// ников, авторизованных у никсерва.
	// Автоидентификаци делается только для зарегистрированных
	// у бота ников.
	boolean registeredNick = false;
	
	// ID ника в базе никсерва, закрепленный за этим ником.
	int registeredNickServID = 0;
	
	// Идентифицировать ли автоматически у бота,
	// если юзер авторизован у никсерва.
	boolean autoIdentify = false;

	static void create() {
		syncGroupIDsString();
	}

	string nick() {
		return id > 0 ? usernick : "3" + usernick;
	}

	/**
	 * Синхронизирует строку, содержащую ID групп со списком ID групп.
	 */
	void syncGroupIDsString() {
		gids_string = "";
		foreach(indices(groupIDs), int gid) {
			gids_string += (gids_string > "" ? "," : "") + (string)gid;
		}
	}
	
	/**
	 * Возвращает строку, содержащую разделённый запятыми список ID групп,
	 * в которые входит пользователь.
	 * @return строку, содержащую разделённый запятыми список ID групп.
	 */
	string getGroupIDsString() {
		return gids_string;
	}
	
	/**
	 * Возвращает строку, содержащую разделённый запятыми список названий групп,
	 * в которые входит пользователь.
	 * @return список названий групп.
	 */
	string getGroupNames(void|UserGroupNameType nt) {
		return getUserGroupNames(groupIDs, nt);
	}
} // class User

// Пользователи, находящиеся на канале.
mapping(string:User) users = ([ ]);




class Player {
	int    id    = 0; // номер в списке игроков
	string usernick  = "";
	string address   = "";
	int    userId    = 0; // ID юзера в базе

	int    alive   = 0; // 2-выбывший до начала игры 3-выбывший из игры 10-в игре 13-вне игры, в ожидании
	int    level   = 0;
	int    roleRejectsLeft = 0;
	int    waitingForAcceptRole = 0;
	string offeredRoles  = "";
	string role    = ROLE_CITIZEN;
	string team    = TEAM_CITIZEN;
	int    won   = 0;

	int    money   = 0;
	int    hostaged  = false;
	int    arrested  = false;
	int    infectedBySlut  = false;

	int    invitedToOffice = false;
	int    invitedToLogovo = false;

	int    checkedByBomzh  = false;
	int    checkedByCattani = false;

	string mayBeRecruitedBy = "";
	string mayChangeTeamTo = "";
	int    changedTeam = false;

	string candidate = "";
	string votingYesNo = "";         // Голосовал да или нет

	string guardianNick  = "";
	int    guardianMoney = 0;

	string killerNick  = "";
	int    killerMoney = 0;

	int    turnsPassed = 0;
	int    votingsPassed = 0; // кол-во пропущенных голосований. Используется для выкидывания спящих.
	int    orderWarning  = 0; // для предупреждений о заказах игроков своей команды

	int    skippedAll  = 0;
	int    getMoneysLeft = 0;

	array(string) invitedChannels = ({ }); // На какие логовы или офисы был приглашён

	boolean waitingForAcceptGun = false; // Только для миров: предложили ли игроку пистолет.
	boolean hasGun = false; // Только для миров: есть ли у игрока пистолет.
	boolean hadGun = false; // Только для миров: был ли у игрока пистолет. Используется при отображении результатов в конце игры.

	mapping(string:mixed) artifacts = ([ ]); // Купленные игроком артефакты и их количество.
	
	// Кем выглядел игрок при проверке катаном/бомжом/хакером.
	// Используется при отображении союзников офиса, чтобы не палить
	// мафов, попавших в офис по украденным журом документам.
	string officeCheckedRole = "";
	
	// Кем выглядел игрок при проверке журналистом.
	// Используется, чтобы не сбивать роль, которой игрок
	// выглядел при проверке офисом, и наоборот.
	// Пример: катан проверяет маньяка с фальшивым паспортом,
	// и маньяк выглядит для катана миром. После проверки
	// паспорт пропадает (допустим, он одноразовый), и маньяка
	// проверяет журналист. Если бы свойство было одно, то
	// перестали бы работать все команды, вычисляющие союзников,
	// типа !allies, !players с включенной подсветской союзников
	// и т.д.
	string logovoCheckedRole = "";
	
	// хочет ли игрок замениться.
	boolean wantsReplace = false;
	
	// игрок автоматически был поставлен ботом в список замен
	// из-за выхода с канала во время игры.
	boolean autoReplace = false;
	
	// тут копятся ники игроков, которых заменил этот игрок.
	// при замене этого игрока другим, накопленные игроки
	// перейдут к тому, кто заменил этого игрока.
	// Используется при выводе результатов игры.
	array(string) replacedPlayers = ({ });

	// Игрок не может голосовать, т.к. его заказала девка 4-го уровня или хулиган.
	boolean skipsVoting = false;
	boolean skipsTurn = false; // Игрок не может ходить ночью, т.к. его заказал хулиган.

	boolean invitedToHooligan = false; // Игрок завербовался в шайку хулигана.
	
	// Максимальный уровень, достигнутый за игру.
	// Используется, чтобы не повторять по несколько раз
	// подсказку ролям you_can_voice_now.
	int maxLevel = 0;
	
	// Взят ли в заложники террористом текущей ночью.
	boolean isHostage = false;
	
	// Был ли взят в заложники террористом не текущей ночью,
	// а в одну из предыдущих ночей.
	// Используется при проверке ночных ходов для вычисления
	// того, кто из заложников недосягаем для заказов.
	// Для заказов недосягаем только те заложники, у которых
	// wasHostage == true.
	boolean wasHostage = false;
	
	// Сколько раз пропускал ход командой !skip.
	int skipCount = 0;
	
	// Суммы выкупов за этого игрока, предложенные другими игроками.
	// mapping(string nick : int money) redeems;
	mapping(string:int) redeems = ([ ]);
	
	// Данные о ночном заказе.
	string orderCommand = "";    // код команды (checkC, killF и т.п.)
	string orderNick = "";       // ник заказанного игрока.
	string orderPhrase = "";     // фраза заказа.
	int    orderLevel = 0;       // уровень команды.
	string previousNick = "";    // ник предыдущего заказанного игрока.
	int    sameNicksCounter = 0; // число заказов _подряд_ одного и того же ника.


	string nick() {
		return (userId > 0) ? usernick : "3" + usernick;
	}

	/**
	 * Проверяет, есть ли у игрока артефакт.
	 * @param code - код или синоним артефакта.
	 * @return true - есть, false - нет.
	 */
	boolean hasArtifact(string code) {
		return artifacts[getArtifactCode(code)] > 0;
	}
	
	/**
	 * Уменьшает на единицу количество артефакта у игрока, если
	 * этот артефакт имеет свойство disposable = yes.
	 * @param code - код или синоним артефакта.
	 * @return новое количество артефакта.
	 * @throws NullPointerException если артефакт с кодом/синонимом code не найден.
	 */
	int disposeArtifact(string code) {
//log(debug_log, sprintf("disposeArtifact: usernick='%O', code='%O', resolved code='%O', ::artifacts[code]->disposable=%O, this->artifacts[code]=%O\n", usernick, code, getArtifactCode(code), global::artifacts[code]->disposable, artifacts[code]));
		code = getArtifactCode(code);
		Artifact a = global::artifacts[code];
		//if (zero_type(a)) { return 0; } Закомментировано, ибо нефиг сюда всякий хлам передавать.
		if (a->disposable && artifacts[code] > 0) {
			artifacts[code]--;
		}
		return artifacts[code];
	}

	/**
	 * Создает копию объекта.
	 * Используется при замене игроков вместо copy_value(),
	 * т.к. copy_value() НЕ создает новый объект.
	 * @return копию объекта.
	 */
	this_program clone() {
		this_program c = this_program();
		foreach (indices(this), string prop) {
			mixed v = this[prop];
			if (!functionp(v)) {
				c[prop] = v;
			}
		}
		return c;
	}
	
} // class Player

// Игроки.
mapping(string:Player) players = ([ ]);


class Commands {
	inherit ACLCacheContainer;

	// deprecated. used for export only.
	UserLevel level = UL_GUEST;

	int id = 0; // ID в базе
	string name = "";
	string group = "";
	string source = "";
	array synonimes = ({ });


	static void create() {
		ACLCacheContainer::create( ({ "ACL_EXECUTE", "ACL_ASSIGN" }) );
	}

	/**
	 * Возвращает разделенный запятыми список названий источников команды.
	 */
	public string getSourceNames() {
		string s = "";
		foreach (source / "", string code) {
			s += (s > "" ? ", " : "") + sprintf("<night>%s</night>", commandSources[code]);
		}
		return s;
	}
}

mapping(string:Commands)  commands = ([ ]);
// для ускорения вывода хелпа.
mapping(string:array(string)) commandsByGroups = ([ ]);

// Источники команд.
// Hashtable<String code, String name> commandSources;
mapping(string:string) commandSources = ([ ]);



class UserlevelName {
	string name  = "";
	string subname = "";
	string multiples = "";
}

mapping(int:UserlevelName)  userlevelName = ([ ]);



class BanList {
	string TIMESTAMP;
	string NICK;
	string ADDRESS;
	int    UNBANTIME;
	string OPERATOR_NICK;
	string REASON;
	int OPERATOR_ID;
}

mapping(string:BanList)   banList   = ([ ]);




// Маска для задания бана.
// Специальные символы (wildcards):
//   * - ноль или более символов.
//   ? - один любой символ.
class AddressMask
{
   string mask;
   Regexp.SimpleRegexp mask_re;

   /**
    * @param mask - маска.
    */
   static void create(void|string mask)
   {
      set(mask || "");
   }

   public void set(string mask)
   {
      string mask_re_str = replace(
         replace(mask, (["\\": "\\\\"]) ),
         ([
         "?": "(.)",  "*":  "(.*)",
         ".": "\\.",  "+":  "\\+",
         "^": "\\^",  "$":  "\\$",
         "(": "\\(",  ")":  "\\)",
         "[": "\\[",  "]":  "\\]",
         "{": "\\{",  "}":  "\\}",
         "<": "\\<",  ">":  "\\>",
         "|": "\\|"
         ]) );
      this->mask = mask;
      mask_re = Regexp.SimpleRegexp("^" + mask_re_str + "$");
   }

   public string get()
   {
      return mask;
   }

   public boolean matches(string mask)
   {
      return mask_re->match(mask);
   }
} // class AddressMask

// Клон, зарегестрированный в таблице CLONES.
class Clone
{
   int id; // CLONES.id.
   string timestamp; // CLONES.timestamp.
   AddressMask address = AddressMask(); // CLONES.address.
   int added_by; // CLONES.addedby.
   string comment; // CLONES.comment.
   
   static void create(int id, string timestamp, string address, int added_by, string comment)
   {
      this->id = id;
      this->timestamp = timestamp;
      this->address->set(address);
      this->added_by = added_by;
      this->comment = comment;
   }
   
   public boolean matches(string address)
   {
      return this->address->matches(address);
   }
   
   public string toString()
   {
      return sprintf("[Clone: id=%d, timestamp=%s, address='%s', added_by=%d, comment='%s']",
         id, timestamp, address->get(), added_by, comment);
   }
} // class Clone

// Клоны, зарегестрированные в таблице CLONES.
// map<int cloneID, Clone clone> clones;
mapping(int:Clone) clones = ([ ]);


class BlockedHost
{
	int id = 0; // ID в базе
	string timestamp = "";
	AddressMask address = AddressMask();
	int blockedTill = 0;
	string blockedBy = "";
	string reason = "";

	/**
	 * @param id - ID в базе.
	 * @param timestamp - время создания блока.
	 * @param address - адрес/маска хоста.
	 * @param blockedTill - номер игры, до которой действителен блок.
	 * @param blockedBy - ник оператора, поставившего блок.
	 * @param reason - причина блока.
	 */
	static void create(
	   int id,
	   string timestamp,
	   string address,
	   int blockedTill,
	   string blockedBy,
	   string reason)
	{
		this->id = id;
		this->timestamp = timestamp;
		setAddress(address);
		this->blockedTill = blockedTill;
		this->blockedBy = blockedBy;
		this->reason = reason;
	}

	public void setAddress(string address)
	{
		this->address->set(address);
	}
	
	public string getAddress()
	{
	   return address->get();
	}
	
	public boolean matches(string addr)
	{
		return address->matches(addr);
	}
} // class BlockedHost

mapping(int:BlockedHost) blockedHosts = ([ ]);


class BlockedHostsException {
	int id = 0; // ID в базе.
	string timestamp = ""; // время установки
	int userID = 0; // ID юзера в базе.
	string usernick = ""; // ник юзера в базе.
	string addedBy = ""; // ник оператора, поставившего исключение.
	
	static void create(int id, string timestamp, int userID, string usernick, string addedBy) {
		this->id = id;
		this->timestamp = timestamp;
		this->userID = userID;
		this->usernick = usernick;
		this->addedBy = addedBy;
	}
} // class BlockedHostsException

// Hashtable<int id, BlockedHostsException ex> blockedHostsExceptions;
mapping(int:BlockedHostsException) blockedHostsExceptions = ([ ]);


// Игровая фраза.
class Phrase {
	int id; // ID в базе.
	string key; // ключ (код) фразы.
	string text; // текст фразы.
	int ovr = 0; // ID фразы, которую оверрайдит эта.
	int uid = 0; // ID юзера, добавившего фразу в базу.
	
	static void create(int id, string key, string text, void|int ovr, void|int uid) {
		this->id = id;
		this->key = key;
		this->text = text;
		this->ovr = !zero_type(ovr) ? ovr : 0;
		this->uid = !zero_type(uid) ? uid : 0;
	}
} // class Phrase


Msg msg = Msg();
