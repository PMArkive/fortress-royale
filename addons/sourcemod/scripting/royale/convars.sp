/**
 * Copyright (C) 2023  Mikusch
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#pragma semicolon 1
#pragma newdecls required

#define COMMAND_MAX_LENGTH	512

enum struct ConVarData
{
	char name[COMMAND_MAX_LENGTH];
	char value[COMMAND_MAX_LENGTH];
	char initial_value[COMMAND_MAX_LENGTH];
	bool enforce;
}

static StringMap g_ConVars;

void ConVars_Init()
{
	g_ConVars = new StringMap();
	
	fr_enable = CreateConVar("fr_enable", "1", "Enable the plugin?");
	fr_setup_length = CreateConVar("fr_setup_length", "15", "Time before the battle bus takes off.");
	fr_truce_duration = CreateConVar("fr_truce_duration", "60", "Length of the truce period.");
	fr_crate_open_time = CreateConVar("fr_crate_open_time", "3", "Amount of time to open a crate.");
	fr_crate_open_range = CreateConVar("fr_crate_open_range", "64", "Range in HU that players may open crates from.");
	fr_crate_max_drops = CreateConVar("fr_crate_max_drops", "1", "Maximum amount of drops a player can receive from a crate.");
	fr_crate_max_extra_drops = CreateConVar("fr_crate_max_extra_drops", "2", "Maximum amount of extra drops a player can receive from a crate.");
	fr_max_ammo_boost = CreateConVar("fr_max_ammo_boost", "1.5", "Maximum amount of excess ammo that players can carry.", _, true, 1.0);
	
	fr_zone_startdisplay = CreateConVar("fr_zone_startdisplay", "30", "Seconds from round start to start zone display", _, true, 0.0);
	fr_zone_startdisplay_player = CreateConVar("fr_zone_startdisplay_player", "1", "Extra seconds on every player from round start to start zone display", _, true, 0.0);
	fr_zone_display = CreateConVar("fr_zone_display", "15", "Seconds to display next zone before shrink", _, true, 0.0);
	fr_zone_display_player = CreateConVar("fr_zone_display_player", "0.5", "Extra seconds on every player to display next zone before shrink", _, true, 0.0);
	fr_zone_shrink = CreateConVar("fr_zone_shrink", "20", "Seconds to shrink zone to next level", _, true, 0.0);
	fr_zone_shrink_player = CreateConVar("fr_zone_shrink_player", "0.67", "Extra seconds on every player to shrink zone to next level", _, true, 0.0);
	fr_zone_nextdisplay = CreateConVar("fr_zone_nextdisplay", "20", "Seconds after shrink to display next zone", _, true, 0.0);
	fr_zone_nextdisplay_player = CreateConVar("fr_zone_nextdisplay_player", "0", "Extra seconds on every player after shrink to display next zone", _, true, 0.0);
	fr_zone_damage = CreateConVar("fr_zone_damage", "4", "Damage of the zone", _, true, 0.0);
	fr_parachute_auto_height = CreateConVar("fr_parachute_auto_height", "2500", "Minimum height from the ground for parachute to auto-activate.");
	
	fr_health_multiplier[TFClass_Scout] = CreateConVar("fr_health_multiplier_scout", "1.6", "Multiplier to maximum health for Scout.");
	fr_health_multiplier[TFClass_Sniper] = CreateConVar("fr_health_multiplier_sniper", "2", "Multiplier to maximum health for Sniper.");
	fr_health_multiplier[TFClass_Soldier] = CreateConVar("fr_health_multiplier_soldier", "1.75", "Multiplier to maximum health for Soldier.");
	fr_health_multiplier[TFClass_DemoMan] = CreateConVar("fr_health_multiplier_demoman", "2", "Multiplier to maximum health for Demoman.");
	fr_health_multiplier[TFClass_Medic] = CreateConVar("fr_health_multiplier_medic", "1.5", "Multiplier to maximum health for Medic.");
	fr_health_multiplier[TFClass_Heavy] = CreateConVar("fr_health_multiplier_heavy", "1.75", "Multiplier to maximum health for Heavy.");
	fr_health_multiplier[TFClass_Pyro] = CreateConVar("fr_health_multiplier_pyro", "1.6", "Multiplier to maximum health for Pyro.");
	fr_health_multiplier[TFClass_Spy] = CreateConVar("fr_health_multiplier_spy", "1.6", "Multiplier to maximum health for Spy.");
	fr_health_multiplier[TFClass_Engineer] = CreateConVar("fr_health_multiplier_engineer", "1.6", "Multiplier to maximum health for Engineer.");
	
	fr_enable.AddChangeHook(ConVarChanged_OnEnableChanged);
	
	mp_disable_respawn_times = FindConVar("mp_disable_respawn_times");
	spec_freeze_traveltime = FindConVar("spec_freeze_traveltime");
	
	ConVars_AddConVar("tf_powerup_mode", "1");
	ConVars_AddConVar("tf_weapon_criticals", "0");
	ConVars_AddConVar("tf_parachute_maxspeed_xy", "600.0f");
	ConVars_AddConVar("tf_parachute_maxspeed_z", "-200.0f");
	ConVars_AddConVar("tf_spawn_glows_duration", "0");
	ConVars_AddConVar("mp_teams_unbalance_limit", "0");
	ConVars_AddConVar("mp_autoteambalance", "0");
	ConVars_AddConVar("mp_scrambleteams_auto", "0");
	ConVars_AddConVar("mp_forcecamera", "0");
	ConVars_AddConVar("mp_friendlyfire", "1");
}

void ConVars_Toggle(bool enable)
{
	StringMapSnapshot snapshot = g_ConVars.Snapshot();
	for (int i = 0; i < snapshot.Length; i++)
	{
		int size = snapshot.KeyBufferSize(i);
		char[] key = new char[size];
		snapshot.GetKey(i, key, size);
		
		if (enable)
		{
			ConVars_Enable(key);
		}
		else
		{
			ConVars_Disable(key);
		}
	}
	delete snapshot;
}

static void ConVars_AddConVar(const char[] name, const char[] value, bool enforce = true)
{
	ConVar convar = FindConVar(name);
	if (convar)
	{
		// Store convar data
		ConVarData data;
		strcopy(data.name, sizeof(data.name), name);
		strcopy(data.value, sizeof(data.value), value);
		data.enforce = enforce;
		
		g_ConVars.SetArray(name, data, sizeof(data));
	}
	else
	{
		LogError("Failed to find convar with name %s", name);
	}
}

static void ConVars_Enable(const char[] name)
{
	ConVarData data;
	if (g_ConVars.GetArray(name, data, sizeof(data)))
	{
		ConVar convar = FindConVar(data.name);
		
		// Store the current value so we can later reset the convar to it
		convar.GetString(data.initial_value, sizeof(data.initial_value));
		g_ConVars.SetArray(name, data, sizeof(data));
		
		// Update the current value
		convar.SetString(data.value);
		convar.AddChangeHook(ConVarChanged_OnTrackedConVarChanged);
	}
}

static void ConVars_Disable(const char[] name)
{
	ConVarData data;
	if (g_ConVars.GetArray(name, data, sizeof(data)))
	{
		ConVar convar = FindConVar(data.name);
		
		g_ConVars.SetArray(name, data, sizeof(data));
		
		// Restore the convar value
		convar.RemoveChangeHook(ConVarChanged_OnTrackedConVarChanged);
		convar.SetString(data.initial_value);
	}
}

static void ConVarChanged_OnTrackedConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	char[] name = new char[sizeof(ConVarData::name)];
	convar.GetName(name, sizeof(ConVarData::name));
	
	ConVarData data;
	if (g_ConVars.GetArray(name, data, sizeof(data)))
	{
		if (!StrEqual(newValue, data.value))
		{
			strcopy(data.initial_value, sizeof(data.initial_value), newValue);
			g_ConVars.SetArray(name, data, sizeof(data));
			
			// Restore our value if needed
			if (data.enforce)
			{
				convar.SetString(data.value);
			}
		}
	}
}

static void ConVarChanged_OnEnableChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (g_bEnabled != convar.BoolValue)
	{
		TogglePlugin(convar.BoolValue);
	}
}
