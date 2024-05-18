#include <sourcemod>
#include <clientprefs>
#include <tf2_stocks>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define TF_GAMETYPE_ARENA 4

#define LIFE_ALIVE 0
#define LIFE_DEAD 2

#define GHOST_MODEL_RED "models/props_halloween/ghost_no_hat_red.mdl"
#define GHOST_MODEL_BLU "models/props_halloween/ghost_no_hat.mdl"

#define GHOST_PARTICLE "ghost_appearation"

enum struct Player
{
	int iTargetEnt;
	int iPreferences;
	float vecPos[3];
	float vecAng[3];
}

enum GhostPreference
{
	Preference_BeGhost,
	Preference_SeeGhosts,

	Preference_MAX
};

char g_sPreferenceNames[Preference_MAX][] = 
{
	"Menu_BeGhost",
	"Menu_SeeGhost",
};

Player g_Player[MAXPLAYERS];
Cookie g_hCookiesPreferences;

public Plugin myinfo =
{
	name = "[TF2] Ghost Mode",
	author = "Jughead",
	version = "2.0.0",
	url = "https://steamcommunity.com/profiles/76561198241665788"
};

public void OnPluginStart()
{
	g_hCookiesPreferences = new Cookie("ghostmode_preferences", "Ghost mode player preferences", CookieAccess_Protected);

	RegConsoleCmd("sm_ghost", Command_Ghost, "Open ghostmode preferences menu");
	RegConsoleCmd("sm_ghostmode", Command_Ghost, "Open ghostmode preferences menu");

	AddCommandListener(CL_Voicemenu, "voicemenu");
	AddCommandListener(CL_Boo, "boo");

	HookEvent("player_death", Event_PlayerDeath);

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
	PrecacheScriptSound("Halloween.GhostBoo");

	PrecacheModel(GHOST_MODEL_RED);
	PrecacheModel(GHOST_MODEL_BLU);

	Cookies_Refresh();
}

public void OnClientConnected(int iClient)
{
	Preferences_SetAll(iClient, -1);
}

public void OnClientPutInServer(int iClient)
{
	SDKHook(iClient, SDKHook_SetTransmit, Hook_SetTransmit);
	Cookies_OnClientJoin(iClient);
}

public void OnClientDisconnect(int iClient)
{
	Preferences_SetAll(iClient, -1);
}

public void TF2_OnConditionAdded(int iClient, TFCond cond)
{
	if (cond != TFCond_HalloweenGhostMode)
		return;

	g_Player[iClient].iTargetEnt = INVALID_ENT_REFERENCE;

	SetVariantString((TF2_GetClientTeam(iClient) == TFTeam_Red) ? GHOST_MODEL_RED : GHOST_MODEL_BLU);
	AcceptEntityInput(iClient, "SetCustomModel");

	SetEntProp(iClient, Prop_Send, "m_lifeState", LIFE_DEAD);
	SetEntProp(iClient, Prop_Send, "m_nForceTauntCam", 2);
	SetEntProp(iClient, Prop_Send, "m_bUseClassAnimations", false);
}

public void TF2_OnConditionRemoved(int iClient, TFCond cond)
{
	if (cond != TFCond_HalloweenGhostMode)
		return;

	SetVariantString("");
	AcceptEntityInput(iClient, "SetCustomModel");
	SetEntProp(iClient, Prop_Send, "m_nForceTauntCam", 0);
}

Action Hook_SetTransmit(int iClient, int iOther)
{
	if (!IsGhost(iClient) || iOther == iClient)
		return Plugin_Continue;

	// Transmit on round end
	if (GameRules_GetRoundState() == RoundState_TeamWin)
		return Plugin_Continue;

	// Don't transmit to alive players with disabled cookie
	if (IsPlayerAlive(iOther) && !Preferences_Get(iOther, Preference_SeeGhosts))
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
	if (!IsGhost(iClient))
		return Plugin_Continue;

	SetNextGhostTarget(iClient);
	return Plugin_Handled;
}

Action CL_Boo(int iClient, const char[] sCommand, int iArgc)
{
	// 10% chance to play BOO!
	return (GetURandomInt() % 10 == 0) ? Plugin_Continue : Plugin_Handled;
}

void Event_PlayerDeath(Event hEvent, const char[] sName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient == 0 || IsFakeClient(iClient))
		return;

	GetClientAbsOrigin(iClient, g_Player[iClient].vecPos);
	GetClientEyeAngles(iClient, g_Player[iClient].vecAng);

	if (Preferences_Get(iClient, Preference_BeGhost) && !(hEvent.GetInt("death_flags") & TF_DEATHFLAG_DEADRINGER))
		CreateTimer(0.1, Timer_BecomeGhost, GetClientUserId(iClient));
}

void Menu_DisplayMain(int iClient)
{
	Menu hMenu = new Menu(Menu_SelectMain);
	hMenu.SetTitle("%T\n ", "Menu_MainTitle", iClient);

	char sDisplay[64], sInfo[8];
	for (int i = 0; i < sizeof(g_sPreferenceNames); i++)
	{
		bool bEnabled = Preferences_Get(iClient, view_as<GhostPreference>(i));
		Format(sDisplay, sizeof(sDisplay), "%T [%s]", g_sPreferenceNames[i], iClient, bEnabled ? "X" : " ");

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

			if (pref == Preference_BeGhost)
			{
				if (bEnabled)
				{
					if (!IsPlayerAlive(iClient))
						CreateTimer(0.0, Timer_BecomeGhost, GetClientUserId(iClient));
				}
				else if (IsGhost(iClient))
					CancelGhostMode(iClient);
			}
			else
				Menu_DisplayMain(iClient);
		}
		case MenuAction_End: delete hMenu;
	}

	return 0;
}

void CancelGhostMode(int iClient)
{
	TF2_RemoveCondition(iClient, TFCond_HalloweenGhostMode);

	DataPack data;
	CreateDataTimer(0.1, Timer_ResetTeam, data);
	data.WriteCell(GetClientUserId(iClient));
	data.WriteCell(TF2_GetClientTeam(iClient));

	// This is used to enter observer state
	TF2_ChangeClientTeam(iClient, TFTeam_Spectator);
}

void SetNextGhostTarget(int iClient)
{
	int iLastTarget = EntRefToEntIndex(g_Player[iClient].iTargetEnt);
	int iNextTarget = -1, iFirstTarget = -1;

	TFTeam nTeam = TF2_GetClientTeam(iClient);

	bool bArena = (GameRules_GetProp("m_nGameType") == TF_GAMETYPE_ARENA);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;

		// Deny targeting enemies in non-arena mode
		if (!bArena && TF2_GetClientTeam(i) != nTeam)
			continue;

		if (iFirstTarget == -1)
			iFirstTarget = i;

		if (i > iLastTarget) 
		{
			iNextTarget = i;
			break;
		}
	}

	int iTarget = (iNextTarget != -1) ? iNextTarget : iFirstTarget;
	if (iTarget != -1)
	{
		g_Player[iClient].iTargetEnt = EntIndexToEntRef(iTarget);

		float vecPos[3], vecAng[3], vecVel[3];
		GetClientAbsOrigin(iTarget, vecPos);
		GetClientEyeAngles(iTarget, vecAng);
		GetEntPropVector(iTarget, Prop_Data, "m_vecAbsVelocity", vecVel);
		TeleportEntity(iClient, vecPos, vecAng, vecVel);
	}
}

Action Timer_BecomeGhost(Handle hTimer, int iUserid)
{
	int iClient = GetClientOfUserId(iUserid);
	if (iClient == 0 || TF2_GetClientTeam(iClient) <= TFTeam_Spectator || !IsActiveRound())
		return Plugin_Handled;

	TF2_RespawnPlayer(iClient);

	TeleportEntity(iClient, g_Player[iClient].vecPos, g_Player[iClient].vecAng, NULL_VECTOR);
	TE_Particle(GHOST_PARTICLE, g_Player[iClient].vecPos);

	TF2_AddCondition(iClient, TFCond_HalloweenGhostMode);
	return Plugin_Handled;
}

Action Timer_ResetTeam(Handle hTimer, DataPack data)
{
	data.Reset();

	int iClient = GetClientOfUserId(data.ReadCell());
	if (iClient != 0)
		TF2_ChangeClientTeam(iClient, data.ReadCell());

	return Plugin_Handled;
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
		g_Player[iClient].iPreferences |= RoundToNearest(Pow(2.0, float(view_as<int>(Preference_SeeGhosts))));
}

void Cookies_Refresh()
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (IsClientInGame(iClient) && !IsFakeClient(iClient))
			Cookies_RefreshPreferences(iClient);
	}
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

void TE_Particle(const char[] sParticle, float vecPos[3])
{
	static int iTable = INVALID_STRING_TABLE;
	if (iTable == INVALID_STRING_TABLE)
		iTable = FindStringTable("ParticleEffectNames");

	TE_Start("TFParticleEffect");
	TE_WriteNum("m_iParticleSystemIndex", FindStringIndex(iTable, sParticle));
	TE_WriteFloat("m_vecOrigin[0]", vecPos[0]);
	TE_WriteFloat("m_vecOrigin[1]", vecPos[1]);
	TE_WriteFloat("m_vecOrigin[2]", vecPos[2]);
	TE_SendToAll();
}

bool IsGhost(int iClient)
{
	return TF2_IsPlayerInCondition(iClient, TFCond_HalloweenGhostMode);
}