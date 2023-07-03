#include <sourcemod>
#include <clientprefs>
#include <tf2_stocks>
#include <sdkhooks>
#include <dhooks>

#pragma semicolon 1
#pragma newdecls required

#define TF_MAXPLAYERS 34

#define LIFE_ALIVE 0
#define LIFE_DEAD 2

#define SOLID_NONE 0
#define SOLID_BBOX 2

#define FSOLID_NOT_SOLID 4
#define FSOLID_NOT_STANDABLE 16

#define COLLISION_GROUP_DEBRIS 1
#define COLLISION_GROUP_PLAYER 5

#define HIDEHUD_HEALTH 8

#define GHOST_COLOR_RED { 159, 55, 34, 255 }
#define GHOST_COLOR_BLU { 76, 109, 129, 255 }

#define GHOST_MODEL_RED "models/props_halloween/ghost_no_hat_red.mdl"
#define GHOST_MODEL_BLU "models/props_halloween/ghost_no_hat.mdl"

#define GHOST_PARTICLE "ghost_appearation"

enum GhostState
{
	State_Ignore,	// Ignored
	State_Ready,	// Ready to become ghost
	State_Ghost	// Ghost
};

enum struct Player
{
	GhostState iState;

	int iTargetEnt;
	int iPreferences;
	float vecPos[3];
	float vecAng[3];

	bool IsGhost() { return this.iState == State_Ghost; }
	bool IsReady() { return this.iState == State_Ready && IsActiveRound(); }
}

enum GhostPreference
{
	Preference_BeGhost,
	Preference_SeeGhost,
	Preference_ThirdPerson,

	Preference_MAX
};

char g_sPreferenceNames[Preference_MAX][] = 
{
	"Menu_BeGhost",
	"Menu_SeeGhost",
	"Menu_ThirdPerson"
};

Player g_Player[TF_MAXPLAYERS];
Handle g_hSDKGetBaseEntity;
Cookie g_hCookiesPreferences;

public Plugin myinfo =
{
	name = "[TF2] Ghost Mode",
	author = "Jughead",
	version = "1.9",
	url = "https://steamcommunity.com/profiles/76561198241665788"
};

public void OnPluginStart()
{
	g_hCookiesPreferences = new Cookie("ghostmode_preferences", "Ghost mode player preferences", CookieAccess_Protected);

	RegConsoleCmd("sm_ghost", Command_Ghost, "Open ghostmode preferences menu");
	RegConsoleCmd("sm_ghostmode", Command_Ghost, "Open ghostmode preferences menu");

	AddCommandListener(CL_Voicemenu, "voicemenu");
	AddCommandListener(CL_Joinclass, "joinclass");
	AddCommandListener(CL_Joinclass, "join_class");
	AddCommandListener(CL_Jointeam, "jointeam");
	AddCommandListener(CL_Jointeam, "spectate");
	AddCommandListener(CL_Jointeam, "autoteam");

	HookEvent("player_spawn", Event_PlayerState);
	HookEvent("player_death", Event_PlayerState);

	GameData hGameData = new GameData("ghostmode");
	if (!hGameData)
		SetFailState("Could not find ghostmode.txt gamedata!");

	DynamicDetour detour = DynamicDetour.FromConf(hGameData, "CTFPlayerShared::InCond");
	if (detour)
		detour.Enable(Hook_Post, DHook_CTFPlayerShared_InCond_Post);

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hGameData, SDKConf_Virtual, "CBaseEntity::GetBaseEntity");
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	if (!(g_hSDKGetBaseEntity = EndPrepSDKCall()))
		LogError("Failed to create call: CBaseEntity::GetBaseEntity");

	delete hGameData;

	LoadTranslations("ghostmode.phrases");

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i))
			OnClientConnected(i);

		if (IsClientInGame(i))
			OnClientPutInServer(i);
	}
}

public void OnMapStart()
{
	PrecacheModel(GHOST_MODEL_RED, true);
	PrecacheModel(GHOST_MODEL_BLU, true);

	Cookies_Refresh();
}

public void OnPluginEnd()
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			Client_CancelGhostMode(i);
}

public void OnClientConnected(int iClient)
{
	Preferences_SetAll(iClient, -1);
}

public void OnClientPutInServer(int iClient)
{
	g_Player[iClient].iState = State_Ignore;
	SDKHook(iClient, SDKHook_SetTransmit, Hook_SetTransmit);
	Cookies_OnClientJoin(iClient);
}

public void OnClientDisconnect(int iClient)
{
	Preferences_SetAll(iClient, -1);
}

public Action OnPlayerRunCmd(int iClient, int &iButtons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (g_Player[iClient].IsGhost())
	{
		iButtons &= ~IN_USE;
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

MRESReturn DHook_CTFPlayerShared_InCond_Post(Address pPlayerShared, DHookReturn ret, DHookParam params)
{
	static int m_Shared = -1;
	if (m_Shared == -1)
		m_Shared = FindSendPropInfo("CTFPlayer", "m_Shared");

	int iClient = SDK_GetBaseEntity(pPlayerShared - view_as<Address>(m_Shared));
	if (iClient <= 0 || iClient > MaxClients)
		return MRES_Ignored;

	if (params.Get(1) == TFCond_HalloweenGhostMode && g_Player[iClient].IsGhost())
	{
		ret.Value = true;
		return MRES_Supercede;
	}

	return MRES_Ignored;
}

Action Hook_SetTransmit(int iClient, int iOther)
{
	if (!g_Player[iClient].IsGhost() || iOther == iClient)
		return Plugin_Continue;

	// Transmit on round end
	if (GameRules_GetRoundState() == RoundState_TeamWin)
		return Plugin_Continue;

	// Don't transmit to alive players with disabled cookie
	if (IsPlayerAlive(iOther) && !Preferences_Get(iOther, Preference_SeeGhost))
		return Plugin_Handled;

	// Transmit to dead/ghost players
	return Plugin_Continue;
}

Action Command_Ghost(int iClient, int iArgc)
{
	if (iClient == 0)
		return Plugin_Handled;

	Menu_DisplayMain(iClient);
	return Plugin_Handled;
}

Action CL_Voicemenu(int iClient, const char[] sCommand, int iArgc)
{
	if (!g_Player[iClient].IsGhost())
		return Plugin_Continue;

	Client_SetNextGhostTarget(iClient);
	return Plugin_Handled;
}

Action CL_Joinclass(int iClient, const char[] sCommand, int iArgc)
{
	if (iArgc < 1 || !g_Player[iClient].IsGhost())
		return Plugin_Continue;

	char sClass[24];
	GetCmdArg(1, sClass, sizeof(sClass));

	if (StrEqual(sClass, "random", false) || StrEqual(sClass, "auto", false))
	{
		SetEntProp(iClient, Prop_Send, "m_iDesiredPlayerClass", GetRandomInt(1, 9));
		return Plugin_Handled;
	}

	TFClassType class = TF2_GetClass(sClass);
	if (class != TFClass_Unknown)
		SetEntProp(iClient, Prop_Send, "m_iDesiredPlayerClass", view_as<int>(class));

	return Plugin_Handled;
}

Action CL_Jointeam(int iClient, const char[] sCommand, int iArgc)
{
	return g_Player[iClient].IsGhost() ? Plugin_Handled : Plugin_Continue;
}

void Event_PlayerState(Event hEvent, const char[] sName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient))
		return;

	if (StrEqual(sName[7], "death"))
	{
		GetClientAbsOrigin(iClient, g_Player[iClient].vecPos);
		GetClientEyeAngles(iClient, g_Player[iClient].vecAng);

		if (Preferences_Get(iClient, Preference_BeGhost) && !(hEvent.GetInt("death_flags") & TF_DEATHFLAG_DEADRINGER))
			CreateTimer(0.1, Timer_Respawn, GetClientUserId(iClient));
	}
	else
		Client_SetGhostMode(iClient, g_Player[iClient].IsReady());
}

void Menu_DisplayMain(int iClient)
{
	Menu hMenu = new Menu(Menu_SelectMain);
	hMenu.SetTitle("%T\n ", "Menu_MainTitle", iClient);

	char sDisplay[64], sInfo[8];
	for (int i = 0; i < sizeof(g_sPreferenceNames); i++)
	{
		bool bEnabled = Preferences_Get(iClient, view_as<GhostPreference>(i));
		Format(sDisplay, sizeof(sDisplay), "%T (%s)", g_sPreferenceNames[i], iClient, bEnabled ? "+" : "-");

		IntToString(i, sInfo, sizeof(sInfo));
		hMenu.AddItem(sInfo, sDisplay);
	}

	hMenu.Display(iClient, MENU_TIME_FOREVER);
}

int Menu_SelectMain(Menu hMenu, MenuAction action, int iClient, int iSelect)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[8];
			hMenu.GetItem(iSelect, sInfo, sizeof(sInfo));

			GhostPreference pref = view_as<GhostPreference>(StringToInt(sInfo));
			bool bEnabled = !Preferences_Get(iClient, pref);
			Preferences_Set(iClient, pref, bEnabled);

			if (pref != Preference_BeGhost)
				Menu_DisplayMain(iClient);

			switch (pref)
			{
				case Preference_BeGhost:
				{
					if (bEnabled)
					{
						Menu_DisplayMain(iClient);
						if (!IsPlayerAlive(iClient))
							CreateTimer(0.1, Timer_Respawn, GetClientUserId(iClient));
					}
					else
						Client_CancelGhostMode(iClient);
				}
				case Preference_ThirdPerson:
				{
					if (g_Player[iClient].IsGhost())
						SetEntProp(iClient, Prop_Send, "m_nForceTauntCam", bEnabled ? 2 : 0);
				}
			}
		}
		case MenuAction_End: delete hMenu;
	}

	return 0;
}

void Client_CancelGhostMode(int iClient)
{
	if (!g_Player[iClient].IsGhost())
		return;

	Client_SetGhostMode(iClient, false);
	SetEntProp(iClient, Prop_Send, "m_lifeState", LIFE_ALIVE);
	SetEntProp(iClient, Prop_Send, "m_nForceTauntCam", 0);
	SDKHooks_TakeDamage(iClient, 0, 0, GetEntProp(iClient, Prop_Send, "m_iHealth") * 1.0);
}

void Client_SetGhostMode(int iClient, bool bState)
{
	g_Player[iClient].iTargetEnt = INVALID_ENT_REFERENCE;
	g_Player[iClient].iState = bState ? State_Ghost : State_Ignore;
	SetCollisions(iClient, bState);

	if (bState)
	{
		SetEntProp(iClient, Prop_Send, "m_lifeState", LIFE_DEAD);
		SetEntProp(iClient, Prop_Send, "m_iHideHUD", HIDEHUD_HEALTH);

		SetGhostModel(iClient);
		SetGhostColor(iClient);

		TeleportEntity(iClient, g_Player[iClient].vecPos, g_Player[iClient].vecAng, NULL_VECTOR);
		TE_Particle(iClient, GHOST_PARTICLE);

		CreateTimer(0.1, Timer_PostGhostMode, GetClientUserId(iClient));
		CreateTimer(0.1, Timer_CheckModel, GetClientUserId(iClient), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		SetVariantString(""); AcceptEntityInput(iClient, "SetCustomModel");
		SetEntityRenderColor(iClient, 255, 255, 255, 255);
	}
}

void Client_SetNextGhostTarget(int iClient)
{
	int iLastTarget = EntRefToEntIndex(g_Player[iClient].iTargetEnt);
	int iNextTarget = -1, iFirstTarget = -1;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || g_Player[i].IsGhost() || !IsPlayerAlive(i))
			continue;

		if (iFirstTarget == -1)
			iFirstTarget = i;

		if (i > iLastTarget) 
		{
			iNextTarget = i;
			break;
		}
	}

	int iTarget = (0 < iNextTarget <= MaxClients && IsClientInGame(iNextTarget)) ? iNextTarget : iFirstTarget;
	if (0 < iTarget <= MaxClients && IsClientInGame(iTarget))
	{
		g_Player[iClient].iTargetEnt = EntIndexToEntRef(iTarget);

		float vecPos[3], vecAng[3], vecVel[3];
		GetClientAbsOrigin(iTarget, vecPos);
		GetClientEyeAngles(iTarget, vecAng);
		GetEntPropVector(iTarget, Prop_Data, "m_vecAbsVelocity", vecVel);
		TeleportEntity(iClient, vecPos, vecAng, vecVel);
	}
}

Action Timer_Respawn(Handle hTimer, int iUserid)
{
	int iClient = GetClientOfUserId(iUserid);
	if (iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient))
		return Plugin_Handled;

	if (IsActiveRound() && TF2_GetClientTeam(iClient) >= TFTeam_Red && !IsFakeClient(iClient))
	{
		g_Player[iClient].iState = State_Ready;
		TF2_RespawnPlayer(iClient);
	}
	else
		g_Player[iClient].iState = State_Ignore;

	return Plugin_Handled;
}

Action Timer_PostGhostMode(Handle hTimer, int iUserid)
{
	int iClient = GetClientOfUserId(iUserid);
	if (iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient) || !g_Player[iClient].IsGhost())
		return Plugin_Handled;

	int iEntity = MaxClients + 1;
	while ((iEntity = FindEntityByClassname(iEntity, "tf_wearable*")) > MaxClients)
	{
		if (GetEntPropEnt(iEntity, Prop_Send, "m_hOwnerEntity") == iClient)
			TF2_RemoveWearable(iClient, iEntity);
	}

	iEntity = MaxClients + 1;
	while ((iEntity = FindEntityByClassname(iEntity, "tf_powerup_bottle")) > MaxClients)
	{
		if (GetEntPropEnt(iEntity, Prop_Send, "m_hOwnerEntity") == iClient)
			AcceptEntityInput(iEntity, "Kill");
	}

	iEntity = MaxClients + 1;
	while ((iEntity = FindEntityByClassname(iEntity, "tf_weapon_spellbook")) > MaxClients)
	{
		if (GetEntPropEnt(iEntity, Prop_Send, "m_hOwnerEntity") == iClient)
			AcceptEntityInput(iEntity, "Kill");
	}

	TF2_RemoveAllWeapons(iClient);

	if (Preferences_Get(iClient, Preference_ThirdPerson))
		SetEntProp(iClient, Prop_Send, "m_nForceTauntCam", 2);

	return Plugin_Handled;
}

Action Timer_CheckModel(Handle hTimer, int iUserid)
{
	int iClient = GetClientOfUserId(iUserid);
	if (iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient) || !g_Player[iClient].IsGhost())
		return Plugin_Stop;

	if (GetEntProp(iClient, Prop_Send, "m_nForceTauntCam") == 1)
		SetEntProp(iClient, Prop_Send, "m_nForceTauntCam", 2);

	char sModel[PLATFORM_MAX_PATH];
	GetEntPropString(iClient, Prop_Send, "m_iszCustomModel", sModel, sizeof(sModel));

	if (!StrEqual(sModel, GHOST_MODEL_RED) && !StrEqual(sModel, GHOST_MODEL_BLU))
		SetGhostModel(iClient);

	return Plugin_Continue;
}

bool IsActiveRound()
{
	RoundState state = GameRules_GetRoundState();
	return (state == RoundState_RoundRunning || state == RoundState_Stalemate);
}

bool Preferences_Get(int iClient, GhostPreference iPreference)
{
	if (g_Player[iClient].iPreferences == -1)
		return false;
	
	return !(g_Player[iClient].iPreferences & RoundToNearest(Pow(2.0, float(view_as<int>(iPreference)))));
}

void Preferences_Set(int iClient, GhostPreference iPreference, bool bEnable)
{
	if (g_Player[iClient].iPreferences == -1)
		return;

	// Since the initial value is 0 to enable all preferences, we set 0 if true, 1 if false
	bEnable = !bEnable;

	if (bEnable)
		g_Player[iClient].iPreferences |= RoundToNearest(Pow(2.0, float(view_as<int>(iPreference))));
	else
		g_Player[iClient].iPreferences &= ~RoundToNearest(Pow(2.0, float(view_as<int>(iPreference))));

	Cookies_SavePreferences(iClient, g_Player[iClient].iPreferences);
}

void Preferences_SetAll(int iClient, int iPreferences)
{
	g_Player[iClient].iPreferences = iPreferences;

	// Disable see ghost cookie by default
	if (iPreferences == 0)
		g_Player[iClient].iPreferences |= RoundToNearest(Pow(2.0, float(view_as<int>(Preference_SeeGhost))));
}

void Cookies_Refresh()
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
		if (IsClientInGame(iClient) && !IsFakeClient(iClient))
			Cookies_RefreshPreferences(iClient);
}

void Cookies_OnClientJoin(int iClient)
{
	if (IsFakeClient(iClient))
	{
		// Bots dont use cookies
		Preferences_SetAll(iClient, 0);
		return;
	}

	Cookies_RefreshPreferences(iClient);
}

void Cookies_RefreshPreferences(int iClient)
{
	int iVal;
	char sVal[16];
	g_hCookiesPreferences.Get(iClient, sVal, sizeof(sVal));

	if (StringToIntEx(sVal, iVal) > 0)
		Preferences_SetAll(iClient, iVal);
	else
		Preferences_SetAll(iClient, 0);
}

void Cookies_SavePreferences(int iClient, int iValue)
{
	if (iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient) || IsFakeClient(iClient))
		return;

	char sVal[16];
	IntToString(iValue, sVal, sizeof(sVal));
	g_hCookiesPreferences.Set(iClient, sVal);
}

void TE_Particle(int iClient, const char[] sParticle)
{
	static int iTable = INVALID_STRING_TABLE;
	if (iTable == INVALID_STRING_TABLE)
		iTable = FindStringTable("ParticleEffectNames");

	TE_Start("TFParticleEffect");
	TE_WriteNum("entindex", iClient);
	TE_WriteNum("m_iParticleSystemIndex", FindStringIndex(iTable, sParticle));
	TE_SendToAll();
}

void SetGhostModel(int iClient)
{
	SetVariantString((TF2_GetClientTeam(iClient) == TFTeam_Red) ? GHOST_MODEL_RED : GHOST_MODEL_BLU);
	AcceptEntityInput(iClient, "SetCustomModel");
}

void SetGhostColor(int iClient)
{
	int iColor[4]; iColor = (TF2_GetClientTeam(iClient) == TFTeam_Red) ? GHOST_COLOR_RED : GHOST_COLOR_BLU;
	SetEntityRenderColor(iClient, iColor[0], iColor[1], iColor[2], iColor[3]);
}

void SetCollisions(int iClient, bool bInGhostMode)
{
	SetEntProp(iClient, Prop_Data, "m_nSolidType", bInGhostMode ? SOLID_NONE : SOLID_BBOX);
	SetEntProp(iClient, Prop_Send, "m_nSolidType", bInGhostMode ? SOLID_NONE : SOLID_BBOX);

	SetEntProp(iClient, Prop_Data, "m_usSolidFlags", bInGhostMode ? FSOLID_NOT_SOLID : FSOLID_NOT_STANDABLE);
	SetEntProp(iClient, Prop_Send, "m_usSolidFlags", bInGhostMode ? FSOLID_NOT_SOLID : FSOLID_NOT_STANDABLE);

	SetEntityCollisionGroup(iClient, bInGhostMode ? COLLISION_GROUP_DEBRIS : COLLISION_GROUP_PLAYER);
	EntityCollisionRulesChanged(iClient);
}

int SDK_GetBaseEntity(Address pEntity)
{
	return SDKCall(g_hSDKGetBaseEntity, pEntity);
}