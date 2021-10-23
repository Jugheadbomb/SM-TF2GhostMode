#include <sourcemod>
#include <clientprefs>
#include <tf2_stocks>
#include <sdkhooks>
#include <dhooks>

#pragma semicolon 1
#pragma newdecls required

#define TF_MAXPLAYERS 32
#define MAX_BUTTONS 26

#define REDCOLOR 255, 75, 75, 100
#define BLUECOLOR 75, 75, 255, 100

#define GHOST_MODEL "models/props_halloween/ghost_no_hat.mdl"
#define GHOST_SPEED 300.0

enum
{
	State_Ignore,	// Ignored
	State_Ready,	// Ready to become ghost
	State_Ghost		// Ghost
}

int g_iPlayerState[TF_MAXPLAYERS + 1];
int g_iPlayerLastButtons[TF_MAXPLAYERS + 1];
int g_iPlayerGhostTarget[TF_MAXPLAYERS + 1];

Cookie g_hGhostCookie;

public Plugin myinfo =
{
	name = "[TF2] Ghost Mode",
	author = "Jughead",
	version = "1.0",
	url = "https://steamcommunity.com/id/jugheadq"
};

public void OnPluginStart()
{
	g_hGhostCookie = new Cookie("ghostmode_preference", "", CookieAccess_Private);
	RegConsoleCmd("sm_ghost", Command_Ghost, "Turn on/off ghostmode");

	AddCommandListener(CL_Voicemenu, "voicemenu");
	AddCommandListener(CL_Joinclass, "joinclass");
	AddCommandListener(CL_Joinclass, "join_class");

	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);

	// Late load
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			OnClientPutInServer(i);

	GameData_Init();
}

public void OnMapStart()
{
	PrecacheModel(GHOST_MODEL, true);
}

public void OnClientPutInServer(int iClient)
{
	g_iPlayerState[iClient] = State_Ignore;

	SDKHook(iClient, SDKHook_PreThink, Hook_PreThink);
	SDKHook(iClient, SDKHook_SetTransmit, Hook_SetTransmit);
}

public void TF2_OnConditionAdded(int iClient, TFCond cond)
{
	if (cond != TFCond_Taunting || !IsClientInGhostMode(iClient))
		return;

	TF2_RemoveCondition(iClient, TFCond_Taunting);
}

public Action OnPlayerRunCmd(int iClient, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	int button;
	for (int i = 0; i < MAX_BUTTONS; i++)
	{
		button = (1 << i);

		if ((buttons & button))
		{
			if (!(g_iPlayerLastButtons[iClient] & button))
				Client_OnButtonPress(iClient, button);
		}
		else if ((g_iPlayerLastButtons[iClient] & button))
			Client_OnButtonRelease(iClient, button);
	}

	g_iPlayerLastButtons[iClient] = buttons;
}

public MRESReturn DHook_PassEntityFilter(DHookReturn ret, DHookParam params)
{
	if (params.IsNull(1) || params.IsNull(2))
		return MRES_Ignored;

	int iEntity1 = params.Get(1);
	int iEntity2 = params.Get(2);

	if (0 < iEntity1 <= MaxClients)
	{
		if (IsClientInGhostMode(iEntity1))
		{
			ret.Value = false;
			return MRES_Supercede;
		}
	}

	if (0 < iEntity2 <= MaxClients)
	{
		if (IsClientInGhostMode(iEntity2))
		{
			ret.Value = false;
			return MRES_Supercede;
		}
	}

	return MRES_Ignored;
}

public void Hook_PreThink(int iClient)
{
	if (!IsClientInGhostMode(iClient))
		return;

	if (GetEntityFlags(iClient) & FL_EDICT_ALWAYS)
		SetEntityFlags(iClient, GetEntityFlags(iClient) ^ FL_EDICT_ALWAYS);

	SetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed", GHOST_SPEED);

	if (GetEntProp(iClient, Prop_Send, "m_nForceTauntCam") == 1)
	{
		SetVariantInt(2);
		AcceptEntityInput(iClient, "SetForcedTauntCam");
	}
}

public Action Hook_SetTransmit(int iClient, int iOther)
{
	// Transmit on round end
	if (GameRules_GetRoundState() == RoundState_TeamWin)
		return Plugin_Continue;

	// Don't transmit to non-ghost players
	if (iOther != iClient && IsClientInGhostMode(iClient) && !IsClientInGhostMode(iOther))
		return Plugin_Handled;

	return Plugin_Continue;
}

public Action Command_Ghost(int iClient, int iArgc)
{
	if (iClient == 0)
		return Plugin_Handled;

	if (Cookie_Get(iClient))
	{
		Cookie_Set(iClient, "0");
		PrintToChat(iClient, "\x07E17100[SM] Ghost mode %s", IsClientInGhostMode(iClient) ? "will be disabled after respawn" : "disabled");
	}
	else
	{
		Cookie_Set(iClient, "1");
		PrintToChat(iClient, "\x07E19F00[SM] Ghost mode enabled");

		if (IsActiveRound() && !IsClientInGhostMode(iClient) && !IsPlayerAlive(iClient))
		{
			g_iPlayerState[iClient] = State_Ready;
			CreateTimer(0.1, Timer_Respawn, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
		}
	}

	return Plugin_Handled;
}

public Action CL_Voicemenu(int iClient, const char[] sCommand, int iArgc)
{
	if (IsClientInGhostMode(iClient))
	{
		Client_SetNextGhostTarget(iClient);
		return Plugin_Handled;
	}

	return Plugin_Continue;
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

public Action Event_PlayerSpawn(Event hEvent, const char[] sName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient))
		return;

	Client_SetGhostMode(iClient, (!IsActiveRound() || g_iPlayerState[iClient] != State_Ready) ? false : true);
}

public Action Event_PlayerDeath(Event hEvent, const char[] sName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	if (iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient))
		return;

	if (!IsActiveRound() || hEvent.GetInt("death_flags") & TF_DEATHFLAG_DEADRINGER)
		return;

	if (Cookie_Get(iClient))
	{
		g_iPlayerState[iClient] = State_Ready;
		CreateTimer(0.1, Timer_Respawn, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
	}
}

void Client_SetGhostMode(int iClient, bool bState)
{
	g_iPlayerGhostTarget[iClient] = INVALID_ENT_REFERENCE;

	if (bState)
	{
		g_iPlayerState[iClient] = State_Ghost;

		SetEntProp(iClient, Prop_Send, "m_bDrawViewmodel", false);
		SetEntProp(iClient, Prop_Send, "m_CollisionGroup", 1);
		SetEntProp(iClient, Prop_Send, "m_lifeState", 2); // Magic
		SetEntProp(iClient, Prop_Send, "m_iHideHUD", 8);

		// Set class to spy to see enemy health
		SetEntProp(iClient, Prop_Send, "m_iClass", view_as<int>(TFClass_Spy));
		TF2_RegeneratePlayer(iClient);

		SetVariantInt(1);
		AcceptEntityInput(iClient, "SetCustomModelRotates");

		SetVariantString(GHOST_MODEL);
		AcceptEntityInput(iClient, "SetCustomModel");

		SetEntityRenderMode(iClient, RENDER_TRANSCOLOR);
		switch (TF2_GetClientTeam(iClient))
		{
			case TFTeam_Red: SetEntityRenderColor(iClient, REDCOLOR);
			case TFTeam_Blue: SetEntityRenderColor(iClient, BLUECOLOR);
		}

		Client_SetNextGhostTarget(iClient);
		CreateTimer(0.1, Timer_PostGhostMode, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
		CreateTimer(1.0, Timer_RemoveParticles, GetClientUserId(iClient), TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		g_iPlayerState[iClient] = State_Ignore;

		SetEntProp(iClient, Prop_Send, "m_bDrawViewmodel", true);
		SetEntProp(iClient, Prop_Send, "m_CollisionGroup", 5);

		SetVariantString("");
		AcceptEntityInput(iClient, "SetCustomModel");

		SetEntityRenderMode(iClient, RENDER_NORMAL);
		SetEntityRenderColor(iClient, 255, 255, 255, 255);
	}
}

public Action Timer_PostGhostMode(Handle hTimer, any userid)
{
	int iClient = GetClientOfUserId(userid);
	if (iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient) || !IsClientInGhostMode(iClient))
		return;

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

	// Remove all weapons
	for (int i = 0; i <= 5; i++)
		TF2_RemoveWeaponSlot(iClient, i);

	SetVariantInt(2);
	AcceptEntityInput(iClient, "SetForcedTauntCam");
}

public Action Timer_RemoveParticles(Handle hTimer, any userid)
{
	int iClient = GetClientOfUserId(userid);
	if (iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient))
		return;

	SetVariantString("ParticleEffectStop");
	AcceptEntityInput(iClient, "DispatchEffect");
}

public Action Timer_Respawn(Handle hTimer, any userid)
{
	int iClient = GetClientOfUserId(userid);
	if (iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient))
		return;

	if (!IsActiveRound() || TF2_GetClientTeam(iClient) <= TFTeam_Spectator)
	{
		g_iPlayerState[iClient] = State_Ignore;
		return;
	}

	TF2_RespawnPlayer(iClient);
}

void Client_SetNextGhostTarget(int iClient)
{
	int iLastTarget = EntRefToEntIndex(g_iPlayerGhostTarget[iClient]);
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
		g_iPlayerGhostTarget[iClient] = EntIndexToEntRef(iTarget);

		float flPos[3], flAng[3], flVelocity[3];
		GetClientAbsOrigin(iTarget, flPos);
		GetClientEyeAngles(iTarget, flAng);
		GetEntPropVector(iTarget, Prop_Data, "m_vecAbsVelocity", flVelocity);
		TeleportEntity(iClient, flPos, flAng, flVelocity);
	}
}

void Client_OnButtonPress(int iClient, int iButton)
{
	switch (iButton)
	{
		case IN_JUMP:
			SetEntityGravity(iClient, IsClientInGhostMode(iClient) ? 0.0001 : 1.0);
		case IN_DUCK:
			SetEntityGravity(iClient, IsClientInGhostMode(iClient) ? 4.0 : 1.0);
	}
}

void Client_OnButtonRelease(int iClient, int iButton)
{
	switch (iButton)
	{
		case IN_DUCK, IN_JUMP:
			SetEntityGravity(iClient, IsClientInGhostMode(iClient) ? 0.5 : 1.0);
	}
}

bool IsClientInGhostMode(int iClient)
{
	return g_iPlayerState[iClient] == State_Ghost;
}

bool IsActiveRound()
{
	RoundState state = GameRules_GetRoundState();
	return state == RoundState_RoundRunning || state == RoundState_Stalemate; // Valve?
}

bool Cookie_Get(int iClient)
{
	char sValue[8];
	g_hGhostCookie.Get(iClient, sValue, sizeof(sValue));
	if (!sValue[0] || StringToInt(sValue))
		return true;

	return false;
}

void Cookie_Set(int iClient, const char[] sValue)
{
	g_hGhostCookie.Set(iClient, sValue);
}

void GameData_Init()
{
	GameData hGameData = new GameData("ghostmode");
	if (!hGameData)
		SetFailState("Could not find ghostmode.txt gamedata!");

	DynamicDetour detour = DynamicDetour.FromConf(hGameData, "PassEntityFilter");
	if (!detour.Enable(Hook_Post, DHook_PassEntityFilter))
		LogError("Failed to detour \"PassEntityFilter\".");

	delete hGameData;
}