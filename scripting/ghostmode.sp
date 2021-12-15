#include <sourcemod>
#include <clientprefs>
#include <tf2_stocks>
#include <sdkhooks>
#include <dhooks>

#pragma semicolon 1
#pragma newdecls required

#define TF_MAXPLAYERS		33

#define GHOST_COLOR_RED		{ 159, 55, 34, 255 }
#define GHOST_COLOR_BLUE	{ 76, 109, 129, 255 }

#define GHOST_MODEL_RED		"models/props_halloween/ghost_no_hat_red.mdl"
#define GHOST_MODEL_BLUE	"models/props_halloween/ghost_no_hat.mdl"

#define GHOST_SPEED			375.0 // -20% in TFCond_SwimmingNoEffects (300)
#define GHOST_PARTICLE		"ghost_appearation"

enum
{
	State_Ignore,	// Ignored
	State_Ready,	// Ready to become ghost
	State_Ghost		// Ghost
}

enum struct Player
{
	int iState;
	int iTargetEnt;
	float flPos[3];
	float flAng[3];
}

Player g_Player[TF_MAXPLAYERS + 1];

Cookie g_hBeGhostCookie;
Cookie g_hSeeGhostCookie;
Cookie g_hThirdPersonCookie;

public Plugin myinfo =
{
	name = "[TF2] Ghost Mode",
	author = "Jughead",
	version = "1.4",
	url = "https://steamcommunity.com/id/jugheadq"
};

public void OnPluginStart()
{
	g_hBeGhostCookie = new Cookie("ghostmode_beghost", "", CookieAccess_Private);
	g_hSeeGhostCookie = new Cookie("ghostmode_seeghost", "", CookieAccess_Private);
	g_hThirdPersonCookie = new Cookie("ghostmode_thirdperson", "", CookieAccess_Private);

	RegConsoleCmd("sm_ghost", Command_Ghost, "Open ghostmode main menu");
	RegConsoleCmd("sm_ghostmode", Command_Ghost, "Open ghostmode main menu");

	AddCommandListener(CL_Voicemenu, "voicemenu");
	AddCommandListener(CL_Joinclass, "joinclass");
	AddCommandListener(CL_Joinclass, "join_class");

	HookEvent("player_spawn", Event_PlayerState);
	HookEvent("player_death", Event_PlayerState);

	GameData_Init();
	LoadTranslations("ghostmode.phrases");

	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			OnClientPutInServer(i);
}

public void OnMapStart()
{
	PrecacheModel(GHOST_MODEL_RED, true);
	PrecacheModel(GHOST_MODEL_BLUE, true);
}

public void OnPluginEnd()
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			Client_CancelGhostMode(i);
}

public void OnClientPutInServer(int iClient)
{
	g_Player[iClient].iState = State_Ignore;
	SDKHook(iClient, SDKHook_PreThink, Hook_PreThink);
	SDKHook(iClient, SDKHook_SetTransmit, Hook_SetTransmit);
}

public MRESReturn DHook_PassEntityFilter(DHookReturn ret, DHookParam params)
{
	if (params.IsNull(1) || params.IsNull(2))
		return MRES_Ignored;

	int iEntity = params.Get(1);
	if (0 < iEntity <= MaxClients && IsClientInGhostMode(iEntity))
	{
		ret.Value = false;
		return MRES_Supercede;
	}

	iEntity = params.Get(2);
	if (0 < iEntity <= MaxClients && IsClientInGhostMode(iEntity))
	{
		ret.Value = false;
		return MRES_Supercede;
	}

	return MRES_Ignored;
}

public void Hook_PreThink(int iClient)
{
	if (IsClientInGhostMode(iClient) && GetEntProp(iClient, Prop_Send, "m_nForceTauntCam") == 1)
		SetEntProp(iClient, Prop_Send, "m_nForceTauntCam", 2);
}

public Action Hook_SetTransmit(int iClient, int iOther)
{
	if (!IsClientInGhostMode(iClient) || iOther == iClient)
		return Plugin_Continue;

	// Transmit on round end
	if (GameRules_GetRoundState() == RoundState_TeamWin)
		return Plugin_Continue;

	// Transmit to non-ghost players with enabled cookie
	if (!IsClientInGhostMode(iOther))
		return Cookie_Get(iOther, g_hSeeGhostCookie) ? Plugin_Continue : Plugin_Handled;

	return Plugin_Continue;
}

public Action Command_Ghost(int iClient, int iArgc)
{
	if (iClient == 0)
		return Plugin_Handled;

	Menu_DisplayMain(iClient);
	return Plugin_Handled;
}

public Action CL_Voicemenu(int iClient, const char[] sCommand, int iArgc)
{
	if (!IsClientInGhostMode(iClient))
		return Plugin_Continue;

	Client_SetNextGhostTarget(iClient);
	return Plugin_Handled;
}

public Action CL_Joinclass(int iClient, const char[] sCommand, int iArgc)
{
	if (iArgc < 1 || !IsClientInGhostMode(iClient))
		return Plugin_Continue;

	char sClass[24];
	GetCmdArg(1, sClass, sizeof(sClass));

	TFClassType class = TF2_GetClass(sClass);
	if (class != TFClass_Unknown)
		SetEntProp(iClient, Prop_Send, "m_iDesiredPlayerClass", view_as<int>(class));

	return Plugin_Handled;
}

public void Event_PlayerState(Event hEvent, const char[] sName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient))
		return;

	if (StrEqual(sName[7], "spawn"))
	{
		Client_SetGhostMode(iClient, (IsActiveRound() && g_Player[iClient].iState == State_Ready));
		return;
	}

	GetClientAbsOrigin(iClient, g_Player[iClient].flPos);
	GetClientEyeAngles(iClient, g_Player[iClient].flAng);

	if (hEvent.GetInt("death_flags") & TF_DEATHFLAG_DEADRINGER)
		return;

	if (IsActiveRound() && Cookie_Get(iClient, g_hBeGhostCookie))
		CreateTimer(0.1, Timer_Respawn, GetClientUserId(iClient));
}

void Menu_DisplayMain(int iClient)
{
	Menu hMenu = new Menu(Menu_SelectMain);
	hMenu.SetTitle("%T\n ", "Menu_MainTitle", iClient);

	char sBuffer[256];

	Format(sBuffer, sizeof(sBuffer), "%T (%s)", "Menu_BeGhost", iClient, Cookie_Get(iClient, g_hBeGhostCookie) ? "+" : "-");
	hMenu.AddItem("beghost", sBuffer);

	Format(sBuffer, sizeof(sBuffer), "%T (%s)", "Menu_SeeGhost", iClient, Cookie_Get(iClient, g_hSeeGhostCookie) ? "+" : "-");
	hMenu.AddItem("seeghost", sBuffer);

	Format(sBuffer, sizeof(sBuffer), "%T (%s)", "Menu_ThirdPerson", iClient, Cookie_Get(iClient, g_hThirdPersonCookie) ? "+" : "-");
	hMenu.AddItem("thirdperson", sBuffer);

	hMenu.Display(iClient, MENU_TIME_FOREVER);
}

public int Menu_SelectMain(Menu hMenu, MenuAction action, int iClient, int iSelect)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sInfo[32];
			hMenu.GetItem(iSelect, sInfo, sizeof(sInfo));

			if (StrEqual(sInfo, "beghost"))
			{
				bool bValue = !Cookie_Get(iClient, g_hBeGhostCookie);
				Cookie_Set(iClient, g_hBeGhostCookie, bValue);

				if (bValue)
				{
					Menu_DisplayMain(iClient);
					if (!IsPlayerAlive(iClient))
						CreateTimer(0.1, Timer_Respawn, GetClientUserId(iClient));
				}
				else
					Client_CancelGhostMode(iClient);
			}
			else if (StrEqual(sInfo, "seeghost"))
			{
				Cookie_Set(iClient, g_hSeeGhostCookie, !Cookie_Get(iClient, g_hSeeGhostCookie));
				Menu_DisplayMain(iClient);
			}
			else if (StrEqual(sInfo, "thirdperson"))
			{
				bool bValue = !Cookie_Get(iClient, g_hThirdPersonCookie);
				Cookie_Set(iClient, g_hThirdPersonCookie, bValue);
				Menu_DisplayMain(iClient);

				if (IsClientInGhostMode(iClient))
					SetEntProp(iClient, Prop_Send, "m_nForceTauntCam", bValue ? 2 : 0);
			}
		}
		case MenuAction_End: delete hMenu;
	}

	return 0;
}

void Client_CancelGhostMode(int iClient)
{
	if (!IsClientInGhostMode(iClient))
		return;

	Client_SetGhostMode(iClient, false);
	SetEntProp(iClient, Prop_Send, "m_lifeState", 0);
	SetEntProp(iClient, Prop_Send, "m_nForceTauntCam", 0);
	ForcePlayerSuicide(iClient);
}

void Client_SetGhostMode(int iClient, bool bState)
{
	g_Player[iClient].iTargetEnt = INVALID_ENT_REFERENCE;
	g_Player[iClient].iState = bState ? State_Ghost : State_Ignore;
	SetEntProp(iClient, Prop_Send, "m_CollisionGroup", bState ? 1 : 5);

	if (bState)
	{
		TF2_AddCondition(iClient, TFCond_SwimmingNoEffects);
		SetEntProp(iClient, Prop_Send, "m_lifeState", 2);
		SetEntProp(iClient, Prop_Send, "m_iHideHUD", 8);

		SetVariantString(TF2_GetClientTeam(iClient) == TFTeam_Red ? GHOST_MODEL_RED : GHOST_MODEL_BLUE);
		AcceptEntityInput(iClient, "SetCustomModel");

		int iColor[4]; iColor = TF2_GetClientTeam(iClient) == TFTeam_Red ? GHOST_COLOR_RED : GHOST_COLOR_BLUE;
		SetEntityRenderColor(iClient, iColor[0], iColor[1], iColor[2], iColor[3]);

		TeleportEntity(iClient, g_Player[iClient].flPos, g_Player[iClient].flAng);
		TE_Particle(iClient, GHOST_PARTICLE);
		CreateTimer(0.1, Timer_PostGhostMode, GetClientUserId(iClient));
	}
	else
	{
		SetVariantString("");
		AcceptEntityInput(iClient, "SetCustomModel");
		SetEntityRenderColor(iClient, 255, 255, 255, 255);
	}
}

public Action Timer_PostGhostMode(Handle hTimer, any userid)
{
	int iClient = GetClientOfUserId(userid);
	if (iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient) || !IsClientInGhostMode(iClient))
		return Plugin_Continue;

	int iEntity = MaxClients + 1;
	while ((iEntity = FindEntityByClassname(iEntity, "tf_wearable")) > MaxClients)
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
	SetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed", GHOST_SPEED);

	if (Cookie_Get(iClient, g_hThirdPersonCookie))
		SetEntProp(iClient, Prop_Send, "m_nForceTauntCam", 2);

	return Plugin_Continue;
}

public Action Timer_Respawn(Handle hTimer, any userid)
{
	int iClient = GetClientOfUserId(userid);
	if (iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient))
		return Plugin_Continue;

	if (IsActiveRound() && TF2_GetClientTeam(iClient) >= TFTeam_Red)
	{
		g_Player[iClient].iState = State_Ready;
		TF2_RespawnPlayer(iClient);
	}
	else
		g_Player[iClient].iState = State_Ignore;

	return Plugin_Continue;
}

void Client_SetNextGhostTarget(int iClient)
{
	int iLastTarget = EntRefToEntIndex(g_Player[iClient].iTargetEnt);
	int iNextTarget = -1, iFirstTarget = -1;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsClientInGhostMode(i) || !IsPlayerAlive(i))
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

		float flPos[3], flAng[3], flVel[3];
		GetClientAbsOrigin(iTarget, flPos);
		GetClientEyeAngles(iTarget, flAng);
		GetEntPropVector(iTarget, Prop_Data, "m_vecAbsVelocity", flVel);
		TeleportEntity(iClient, flPos, flAng, flVel);
	}
}

bool IsClientInGhostMode(int iClient)
{
	return g_Player[iClient].iState == State_Ghost;
}

bool IsActiveRound()
{
	RoundState state = GameRules_GetRoundState();
	return state == RoundState_RoundRunning || state == RoundState_Stalemate;
}

bool Cookie_Get(int iClient, Cookie cookie)
{
	char sValue[8];
	cookie.Get(iClient, sValue, sizeof(sValue));

	if (!sValue[0])
		return cookie != g_hSeeGhostCookie;

	return !!StringToInt(sValue);
}

void Cookie_Set(int iClient, Cookie cookie, bool bValue)
{
	char sValue[8];
	IntToString(view_as<int>(bValue), sValue, sizeof(sValue));
	cookie.Set(iClient, sValue);
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

void GameData_Init()
{
	GameData hGameData = new GameData("ghostmode");
	if (!hGameData)
		SetFailState("Could not find ghostmode.txt gamedata!");

	DynamicDetour detour = DynamicDetour.FromConf(hGameData, "PassEntityFilter");
	if (detour)
		detour.Enable(Hook_Post, DHook_PassEntityFilter);
	else
		LogError("Failed to detour \"PassEntityFilter\".");

	delete hGameData;
}