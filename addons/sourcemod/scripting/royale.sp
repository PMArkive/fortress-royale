#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
#include <dhooks>

#define CONTENTS_REDTEAM	CONTENTS_TEAM1
#define CONTENTS_BLUETEAM	CONTENTS_TEAM2

#include "royale/convar.sp"
#include "royale/sdk.sp"
#include "royale/stocks.sp"

public void OnPluginStart()
{
	ConVar_Init();
	SDK_Init();
	
	ConVar_Toggle(true);
	
	for (int client = 1; client <= MaxClients; client++)
		if (IsClientInGame(client))
			OnClientPutInServer(client);
}

public void OnPluginEnd()
{
	ConVar_Toggle(false);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_ShouldCollide, Client_ShouldCollide);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "tf_projectile_pipe"))
		SDKHook(entity, SDKHook_Touch, Pipebomb_Touch);
}

public bool Client_ShouldCollide(int entity, int collisiongroup, int contentsmask, bool originalResult)
{
	if (contentsmask & CONTENTS_REDTEAM || contentsmask & CONTENTS_BLUETEAM)
		return true;
	
	return originalResult;
public void Pipebomb_Touch(int entity, int other)
{
	//This function have team check, change grenade pipe to enemy team
	
	if (other == GetEntPropEnt(entity, Prop_Send, "m_hThrower"))
		return;
	
	TFTeam team = TF2_GetEnemyTeam(other);
	if (team <= TFTeam_Spectator)
		return;
	
	TF2_ChangeTeam(entity, team);
}

}