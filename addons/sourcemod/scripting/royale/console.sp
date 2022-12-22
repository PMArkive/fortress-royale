/**
 * Copyright (C) 2022  Mikusch
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

#pragma newdecls required
#pragma semicolon 1

void Console_Init()
{
	AddCommandListener(CommandListener_DropItem, "dropitem");
}

static Action CommandListener_DropItem(int client, const char[] command, int argc)
{
	// If the player has an item, drop it first
	if (GetEntPropEnt(client, Prop_Send, "m_hItem") != -1)
		return Plugin_Continue;
	
	// The following will be dropped (in that order):
	// - current active weapon
	// - wearables (can't be used as active weapon)
	// - weapons that can't be switched to (as determined by TF2)
	
	int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	int weapon = activeWeapon;
	bool found = (weapon != -1) && ShouldDropWeapon(client, weapon);
	
	if (!found)
	{
		for (int slot = 0; slot <= LOADOUT_POSITION_PDA2; slot++)
		{
			weapon = TF2Util_GetPlayerLoadoutEntity(client, slot);
			if (weapon == -1)
				continue;
			
			if (TF2Util_IsEntityWearable(weapon))
			{
				// Always drop wearables
				found = true;
				break;
			}
			else
			{
				if (ShouldDropWeapon(client, weapon) && !SDKCall_CBaseCombatCharacter_Weapon_CanSwitchTo(client, weapon))
				{
					found = true;
					break;
				}
			}
		}
	}
	
	if (!found)
	{
		if (IsWeaponFists(activeWeapon))
		{
			EmitGameSoundToClient(client, "Player.UseDeny");
			
			char message[64];
			Format(message, sizeof(message), "%T", "Weapon_CannotDropFists", client);
			ShowGameMessage(message, "fists");
		}
		
		return Plugin_Continue;
	}
	
	float vecOrigin[3], vecAngles[3];
	if (!SDKCall_CTFPlayer_CalculateAmmoPackPositionAndAngles(client, weapon, vecOrigin, vecAngles))
		return Plugin_Continue;
	
	char model[PLATFORM_MAX_PATH];
	GetItemWorldModel(weapon, model, sizeof(model));
	
	int droppedWeapon = SDKCall_CTFDroppedWeapon_Create(client, vecOrigin, vecAngles, model, GetEntityAddress(weapon) + FindItemOffset(weapon));
	if (IsValidEntity(droppedWeapon))
	{
		if (TF2Util_IsEntityWeapon(weapon))
		{
			SDKCall_CTFDroppedWeapon_InitDroppedWeapon(droppedWeapon, client, weapon, true);
			
			// If the weapon we just dropped could not be switched to, stay on our current weapon
			if (SDKCall_CBaseCombatCharacter_Weapon_CanSwitchTo(client, weapon))
			{
				SDKCall_CBaseCombatCharacter_SwitchToNextBestWeapon(client, weapon);
			}
		}
		else if (TF2Util_IsEntityWearable(weapon))
		{
			InitDroppedWearable(droppedWeapon, client, weapon, true);
		}
		
		TF2_RemovePlayerItem(client, weapon);
	}
	
	if (IsPlayerAlive(client))
	{
		// If we dropped our melee weapon, get our fists back
		int melee = GetEntityForLoadoutSlot(client, LOADOUT_POSITION_MELEE);
		if (melee == -1)
		{
			GivePlayerFists(client);
		}
	}
	
	return Plugin_Continue;
}
