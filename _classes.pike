#include "_artifacts.pike"

/**
 * ���� �����.
 * ���������������� ������������ ��� ��������� � ����
 * ������ ����� � ������ ����.
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
 * ���� ������ (team).
 * ���������������� ������������ ��� ��������� � ����
 * ������ ����� � ������ ����.
 *
 * ���������� ��� ������������, ����� �� ���� ��������
 * ��� ����������� ������� ����� � _roles.pike, ����:
 * team = ROLE_*; // ����� �������, �� ������ ����_*?
 *
 * �������� ������ ���� �� ����, ������� � ������� ��������
 * ���� �������. �������� ������������� �������, �������.
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
	
	// ��������, �������� � ������� (� ������ ��������).
	string originalKey;
	
	// ���������� ��������� ��������?
	boolean isOvr;
	
	// ���������� ��������� ��������?
	boolean isDescOvr;
	
	// ID � ����.
	// ���� ����� ����, ������ ���� �������� �� �� ����, � �� �����.
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
	int id = 0; // ID ����� � ����

	// � ����� ������ ������ ����.
	// ���� ��������� �������� ������, �� �� �������� ������� syncGroupIDsString().
	multiset(int) groupIDs = (< userGroups[UGC_GUESTS]->id >);

	// ���������� �������� ������ ID �����.
	// ������������ � SQL-������� ��� �������� ���� �� ���������� ������.
	string gids_string = "";

	// ���, �� ������� ����������������� ����: !id ��� ������.
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
	string offeredRoles  = ""; // ��� ������ �� ����

	string title1    = "";
	string title2    = "";

	int    regsSkipped = 0; // ���������� ����������� �����������
	int    skippedAll  = 0;
	int    blockedTill = 0;

	int    lastActivityTime= 0; // ��� �������� �����
	int    floodCounter  = 0; // ������� ����� ��� �������� �����
	int    floodCtrlStartTime= 0; // �����, ����� ��� ������� ����� ������������

	// ����� �� ���� �������� ����� ������.
	boolean wantsReplace = false;
	
	// ���������� � ������ � ������ �����������?
	boolean notifyOnRegStart = false;

	// �������������� ����� ������� �� �����?
	boolean unlimitedRoleRejects = false;
	
	// ����� �������. ��, ������� � ������� RIGHTS ���������.
	int accessRights = 0;

	// ����������� �� � �������� (+r).
	boolean authorizedAtNickServ = false;

	// ID ���� � ���� ��������, �� ������� ������������� ����.
	int authorizedNickServID = 0;

	// ��������������� �� ��� � ����.
	// ������������ ��� ����������������� � ����
	// �����, �������������� � ��������.
	// ���������������� �������� ������ ��� ������������������
	// � ���� �����.
	boolean registeredNick = false;
	
	// ID ���� � ���� ��������, ������������ �� ���� �����.
	int registeredNickServID = 0;
	
	// ���������������� �� ������������� � ����,
	// ���� ���� ����������� � ��������.
	boolean autoIdentify = false;

	static void create() {
		syncGroupIDsString();
	}

	string nick() {
		return id > 0 ? usernick : "3" + usernick;
	}

	/**
	 * �������������� ������, ���������� ID ����� �� ������� ID �����.
	 */
	void syncGroupIDsString() {
		gids_string = "";
		foreach(indices(groupIDs), int gid) {
			gids_string += (gids_string > "" ? "," : "") + (string)gid;
		}
	}
	
	/**
	 * ���������� ������, ���������� ���������� �������� ������ ID �����,
	 * � ������� ������ ������������.
	 * @return ������, ���������� ���������� �������� ������ ID �����.
	 */
	string getGroupIDsString() {
		return gids_string;
	}
	
	/**
	 * ���������� ������, ���������� ���������� �������� ������ �������� �����,
	 * � ������� ������ ������������.
	 * @return ������ �������� �����.
	 */
	string getGroupNames(void|UserGroupNameType nt) {
		return getUserGroupNames(groupIDs, nt);
	}
} // class User

// ������������, ����������� �� ������.
mapping(string:User) users = ([ ]);




class Player {
	int    id    = 0; // ����� � ������ �������
	string usernick  = "";
	string address   = "";
	int    userId    = 0; // ID ����� � ����

	int    alive   = 0; // 2-�������� �� ������ ���� 3-�������� �� ���� 10-� ���� 13-��� ����, � ��������
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
	string votingYesNo = "";         // ��������� �� ��� ���

	string guardianNick  = "";
	int    guardianMoney = 0;

	string killerNick  = "";
	int    killerMoney = 0;

	int    turnsPassed = 0;
	int    votingsPassed = 0; // ���-�� ����������� �����������. ������������ ��� ����������� ������.
	int    orderWarning  = 0; // ��� �������������� � ������� ������� ����� �������

	int    skippedAll  = 0;
	int    getMoneysLeft = 0;

	array(string) invitedChannels = ({ }); // �� ����� ������ ��� ����� ��� ���������

	boolean waitingForAcceptGun = false; // ������ ��� �����: ���������� �� ������ ��������.
	boolean hasGun = false; // ������ ��� �����: ���� �� � ������ ��������.
	boolean hadGun = false; // ������ ��� �����: ��� �� � ������ ��������. ������������ ��� ����������� ����������� � ����� ����.

	mapping(string:mixed) artifacts = ([ ]); // ��������� ������� ��������� � �� ����������.
	
	// ��� �������� ����� ��� �������� �������/������/�������.
	// ������������ ��� ����������� ��������� �����, ����� �� ������
	// �����, �������� � ���� �� ���������� ����� ����������.
	string officeCheckedRole = "";
	
	// ��� �������� ����� ��� �������� �����������.
	// ������������, ����� �� ������� ����, ������� �����
	// �������� ��� �������� ������, � ��������.
	// ������: ����� ��������� ������� � ��������� ���������,
	// � ������ �������� ��� ������ �����. ����� ��������
	// ������� ��������� (��������, �� �����������), � �������
	// ��������� ���������. ���� �� �������� ���� ����, ��
	// ��������� �� �������� ��� �������, ����������� ���������,
	// ���� !allies, !players � ���������� ����������� ���������
	// � �.�.
	string logovoCheckedRole = "";
	
	// ����� �� ����� ����������.
	boolean wantsReplace = false;
	
	// ����� ������������� ��� ��������� ����� � ������ �����
	// ��-�� ������ � ������ �� ����� ����.
	boolean autoReplace = false;
	
	// ��� ������� ���� �������, ������� ������� ���� �����.
	// ��� ������ ����� ������ ������, ����������� ������
	// �������� � ����, ��� ������� ����� ������.
	// ������������ ��� ������ ����������� ����.
	array(string) replacedPlayers = ({ });

	// ����� �� ����� ����������, �.�. ��� �������� ����� 4-�� ������ ��� �������.
	boolean skipsVoting = false;
	boolean skipsTurn = false; // ����� �� ����� ������ �����, �.�. ��� ������� �������.

	boolean invitedToHooligan = false; // ����� ������������ � ����� ��������.
	
	// ������������ �������, ����������� �� ����.
	// ������������, ����� �� ��������� �� ��������� ���
	// ��������� ����� you_can_voice_now.
	int maxLevel = 0;
	
	// ���� �� � ��������� ����������� ������� �����.
	boolean isHostage = false;
	
	// ��� �� ���� � ��������� ����������� �� ������� �����,
	// � � ���� �� ���������� �����.
	// ������������ ��� �������� ������ ����� ��� ����������
	// ����, ��� �� ���������� ���������� ��� �������.
	// ��� ������� ���������� ������ �� ���������, � �������
	// wasHostage == true.
	boolean wasHostage = false;
	
	// ������� ��� ��������� ��� �������� !skip.
	int skipCount = 0;
	
	// ����� ������� �� ����� ������, ������������ ������� ��������.
	// mapping(string nick : int money) redeems;
	mapping(string:int) redeems = ([ ]);
	
	// ������ � ������ ������.
	string orderCommand = "";    // ��� ������� (checkC, killF � �.�.)
	string orderNick = "";       // ��� ����������� ������.
	string orderPhrase = "";     // ����� ������.
	int    orderLevel = 0;       // ������� �������.
	string previousNick = "";    // ��� ����������� ����������� ������.
	int    sameNicksCounter = 0; // ����� ������� _������_ ������ � ���� �� ����.


	string nick() {
		return (userId > 0) ? usernick : "3" + usernick;
	}

	/**
	 * ���������, ���� �� � ������ ��������.
	 * @param code - ��� ��� ������� ���������.
	 * @return true - ����, false - ���.
	 */
	boolean hasArtifact(string code) {
		return artifacts[getArtifactCode(code)] > 0;
	}
	
	/**
	 * ��������� �� ������� ���������� ��������� � ������, ����
	 * ���� �������� ����� �������� disposable = yes.
	 * @param code - ��� ��� ������� ���������.
	 * @return ����� ���������� ���������.
	 * @throws NullPointerException ���� �������� � �����/��������� code �� ������.
	 */
	int disposeArtifact(string code) {
//log(debug_log, sprintf("disposeArtifact: usernick='%O', code='%O', resolved code='%O', ::artifacts[code]->disposable=%O, this->artifacts[code]=%O\n", usernick, code, getArtifactCode(code), global::artifacts[code]->disposable, artifacts[code]));
		code = getArtifactCode(code);
		Artifact a = global::artifacts[code];
		//if (zero_type(a)) { return 0; } ����������������, ��� ����� ���� ������ ���� ����������.
		if (a->disposable && artifacts[code] > 0) {
			artifacts[code]--;
		}
		return artifacts[code];
	}

	/**
	 * ������� ����� �������.
	 * ������������ ��� ������ ������� ������ copy_value(),
	 * �.�. copy_value() �� ������� ����� ������.
	 * @return ����� �������.
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

// ������.
mapping(string:Player) players = ([ ]);


class Commands {
	inherit ACLCacheContainer;

	// deprecated. used for export only.
	UserLevel level = UL_GUEST;

	int id = 0; // ID � ����
	string name = "";
	string group = "";
	string source = "";
	array synonimes = ({ });


	static void create() {
		ACLCacheContainer::create( ({ "ACL_EXECUTE", "ACL_ASSIGN" }) );
	}

	/**
	 * ���������� ����������� �������� ������ �������� ���������� �������.
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
// ��� ��������� ������ �����.
mapping(string:array(string)) commandsByGroups = ([ ]);

// ��������� ������.
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




// ����� ��� ������� ����.
// ����������� ������� (wildcards):
//   * - ���� ��� ����� ��������.
//   ? - ���� ����� ������.
class AddressMask
{
   string mask;
   Regexp.SimpleRegexp mask_re;

   /**
    * @param mask - �����.
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

// ����, ������������������ � ������� CLONES.
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

// �����, ������������������ � ������� CLONES.
// map<int cloneID, Clone clone> clones;
mapping(int:Clone) clones = ([ ]);


class BlockedHost
{
	int id = 0; // ID � ����
	string timestamp = "";
	AddressMask address = AddressMask();
	int blockedTill = 0;
	string blockedBy = "";
	string reason = "";

	/**
	 * @param id - ID � ����.
	 * @param timestamp - ����� �������� �����.
	 * @param address - �����/����� �����.
	 * @param blockedTill - ����� ����, �� ������� ������������ ����.
	 * @param blockedBy - ��� ���������, ������������ ����.
	 * @param reason - ������� �����.
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
	int id = 0; // ID � ����.
	string timestamp = ""; // ����� ���������
	int userID = 0; // ID ����� � ����.
	string usernick = ""; // ��� ����� � ����.
	string addedBy = ""; // ��� ���������, ������������ ����������.
	
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


// ������� �����.
class Phrase {
	int id; // ID � ����.
	string key; // ���� (���) �����.
	string text; // ����� �����.
	int ovr = 0; // ID �����, ������� ���������� ���.
	int uid = 0; // ID �����, ����������� ����� � ����.
	
	static void create(int id, string key, string text, void|int ovr, void|int uid) {
		this->id = id;
		this->key = key;
		this->text = text;
		this->ovr = !zero_type(ovr) ? ovr : 0;
		this->uid = !zero_type(uid) ? uid : 0;
	}
} // class Phrase


Msg msg = Msg();
