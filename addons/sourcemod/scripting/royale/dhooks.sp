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

enum struct DetourData
{
	DynamicDetour detour;
	DHookCallback callback_pre;
	DHookCallback callback_post;
}

static ArrayList g_DynamicDetours;
static ArrayList g_DynamicHookIds;

static DynamicHook g_DHookGiveNamedItem;

void DHooks_Init(GameData gamedata)
{
	g_DynamicDetours = new ArrayList(sizeof(DetourData));
	g_DynamicHookIds = new ArrayList();
	
	g_DHookGiveNamedItem = DHooks_AddDynamicHook(gamedata, "CTFPlayer::GiveNamedItem");
	
	DHooks_AddDynamicDetour(gamedata, "CTFDroppedWeapon::Create", DHookCallback_CTFDroppedWeapon_Create_Pre);
	DHooks_AddDynamicDetour(gamedata, "CTFPlayer::PickupWeaponFromOther", DHookCallback_CTFPlayer_PickupWeaponFromOther_Pre);
	DHooks_AddDynamicDetour(gamedata, "CTFPlayer::CanPickupDroppedWeapon", DHookCallback_CTFPlayer_CanPickupDroppedWeapon_Pre);
}

void DHooks_OnClientPutInServer(int client)
{
	DHooks_HookEntity(g_DHookGiveNamedItem, Hook_Pre, client, DHookCallback_CTFPlayer_GiveNamedItem_Pre);
}

void DHooks_Toggle(bool enable)
{
	for (int i = 0; i < g_DynamicDetours.Length; i++)
	{
		DetourData data;
		if (g_DynamicDetours.GetArray(i, data) != 0)
		{
			if (data.callback_pre != INVALID_FUNCTION)
			{
				if (enable)
					data.detour.Enable(Hook_Pre, data.callback_pre);
				else
					data.detour.Disable(Hook_Pre, data.callback_pre);
			}
			
			if (data.callback_post != INVALID_FUNCTION)
			{
				if (enable)
					data.detour.Enable(Hook_Post, data.callback_post);
				else
					data.detour.Disable(Hook_Post, data.callback_post);
			}
		}
	}
	
	if (!enable)
	{
		for (int i = g_DynamicHookIds.Length - 1; i >= 0; i--)
		{
			int hookid = g_DynamicHookIds.Get(i);
			DynamicHook.RemoveHook(hookid);
		}
	}
}

static void DHooks_AddDynamicDetour(GameData gamedata, const char[] name, DHookCallback callback_pre = INVALID_FUNCTION, DHookCallback callback_post = INVALID_FUNCTION)
{
	DynamicDetour detour = DynamicDetour.FromConf(gamedata, name);
	if (detour)
	{
		DetourData data;
		data.detour = detour;
		data.callback_pre = callback_pre;
		data.callback_post = callback_post;
		
		g_DynamicDetours.PushArray(data);
	}
	else
	{
		LogError("Failed to create detour setup handle for %s", name);
	}
}

static DynamicHook DHooks_AddDynamicHook(GameData gamedata, const char[] name)
{
	DynamicHook hook = DynamicHook.FromConf(gamedata, name);
	if (!hook)
		LogError("Failed to create hook setup handle for %s", name);
	
	return hook;
}

static void DHooks_HookEntity(DynamicHook hook, HookMode mode, int entity, DHookCallback callback)
{
	if (!hook)
		return;
	
	int hookid = hook.HookEntity(mode, entity, callback, DHookRemovalCB_OnHookRemoved);
	if (hookid != INVALID_HOOK_ID)
		g_DynamicHookIds.Push(hookid);
}

static void DHookRemovalCB_OnHookRemoved(int hookid)
{
	int index = g_DynamicHookIds.FindValue(hookid);
	if (index != -1)
		g_DynamicHookIds.Erase(index);
}

static MRESReturn DHookCallback_CTFDroppedWeapon_Create_Pre(DHookReturn ret, DHookParam params)
{
	if (IsInWaitingForPlayers())
		return MRES_Ignored;
	
	// Prevent dropped weapon creation from TF2 itself, we pass NULL to pLastOwner
	if (!params.IsNull(1))
	{
		ret.Value = -1;
		return MRES_Supercede;
	}
	
	return MRES_Ignored;
}

static MRESReturn DHookCallback_CTFPlayer_PickupWeaponFromOther_Pre(int player, DHookReturn ret, DHookParam params)
{
	int droppedWeapon = params.Get(1);
	
	Address pItem = GetEntityAddress(droppedWeapon) + FindItemOffset(droppedWeapon);
	if (!LoadFromAddress(pItem, NumberType_Int32))
	{
		ret.Value = false;
		return MRES_Supercede;
	}
	
	if (GetEntProp(droppedWeapon, Prop_Send, "m_bInitialized"))
	{
		int itemdef = GetEntProp(droppedWeapon, Prop_Send, "m_iItemDefinitionIndex");
		
		TFClassType class = TF2_GetPlayerClass(player);
		int itemSlot = TF2Econ_GetItemLoadoutSlot(itemdef, class);
		int weapon = GetEntityForLoadoutSlot(player, itemSlot);
		
		// we need to force translating the name here.
		// GiveNamedItem will not translate if we force creating the item
		char weaponName[64];
		TF2Econ_GetItemClassName(itemdef, weaponName, sizeof(weaponName));
		TF2Econ_TranslateWeaponEntForClass(weaponName, sizeof(weaponName), class);
		
		int newItem = SDKCall_CTFPlayer_GiveNamedItem(player, weaponName, 0, pItem, true);
		if (IsValidEntity(newItem))
		{
			if (TF2Util_IsEntityWeapon(newItem) && TF2Util_GetWeaponID(newItem) == TF_WEAPON_BUILDER && class == TFClass_Spy)
			{
				SetEntProp(newItem, Prop_Send, "m_iObjectType", TFObject_Sapper);
				SetEntProp(newItem, Prop_Data, "m_iSubType", TFObject_Sapper);
			}
			
			// make sure we removed our current weapon
			if (IsValidEntity(weapon))
			{
				// drop current weapon
				float vecPackOrigin[3], vecPackAngles[3];
				SDKCall_CTFPlayer_CalculateAmmoPackPositionAndAngles(player, weapon, vecPackOrigin, vecPackAngles);
				
				char szWorldModel[PLATFORM_MAX_PATH];
				if (GetItemWorldModel(weapon, szWorldModel, sizeof(szWorldModel)))
				{
					int newDroppedWeapon = CreateDroppedWeapon(player, vecPackOrigin, vecPackAngles, szWorldModel, GetEntityAddress(weapon) + FindItemOffset(weapon));
					if (IsValidEntity(newDroppedWeapon))
					{
						if (TF2Util_IsEntityWeapon(weapon))
						{
							SDKCall_CTFDroppedWeapon_InitDroppedWeapon(newDroppedWeapon, player, weapon, true);
						}
						else if (TF2Util_IsEntityWearable(weapon))
						{
							InitDroppedWearable(newDroppedWeapon, player, weapon, true);
						}
					}
				}
				
				TF2_RemovePlayerItem(player, weapon);
			}
			
			int lastWeapon = GetEntPropEnt(player, Prop_Send, "m_hLastWeapon");
			SetEntProp(newItem, Prop_Send, "m_bValidatedAttachedEntity", true);
			ItemGiveTo(player, newItem);
			SetEntPropEnt(player, Prop_Send, "m_hLastWeapon", lastWeapon);
			
			if (TF2Util_IsEntityWeapon(newItem))
			{
				SDKCall_CTFDroppedWeapon_InitPickedUpWeapon(droppedWeapon, player, newItem);
				
				// can't use the weapon we just picked up?
				if (!SDKCall_CBaseCombatCharacter_Weapon_CanSwitchTo(player, newItem))
				{
					// try next best thing we can use
					SDKCall_CBaseCombatCharacter_SwitchToNextBestWeapon(player, newItem);
				}
			}
			else if (TF2Util_IsEntityWearable(newItem))
			{
				// switch to the next best weapon
				if (GetEntPropEnt(player, Prop_Send, "m_hActiveWeapon") == -1)
				{
					SDKCall_CBaseCombatCharacter_SwitchToNextBestWeapon(player, -1);
				}
			}
			
			// delay pickup weapon message
			FRPlayer(player).m_flSendPickupWeaponMessageTime = GetGameTime() + 0.1;
			
			ret.Value = true;
			return MRES_Supercede;
		}
	}
	
	ret.Value = false;
	return MRES_Supercede;
}

static MRESReturn DHookCallback_CTFPlayer_CanPickupDroppedWeapon_Pre(int player, DHookReturn ret, DHookParam params)
{
	int weapon = params.Get(1);
	
	if (!GetEntProp(weapon, Prop_Send, "m_bInitialized"))
	{
		ret.Value = false;
		return MRES_Supercede;
	}
	
	TFClassType class = TF2_GetPlayerClass(player);
	if (class == TFClass_Spy && (TF2_IsPlayerInCondition(player, TFCond_Disguised) || GetPercentInvisible(player) > 0.0))
	{
		ret.Value = false;
		return MRES_Supercede;
	}
	
	if (TF2_IsPlayerInCondition(player, TFCond_Taunting))
	{
		ret.Value = false;
		return MRES_Supercede;
	}
	
	if (!IsPlayerAlive(player))
	{
		ret.Value = false;
		return MRES_Supercede;
	}
	
	if (GetEntPropEnt(player, Prop_Send, "m_hActiveWeapon") == -1)
	{
		ret.Value = false;
		return MRES_Supercede;
	}
	
	ret.Value = CanWeaponBeUsedByClass(weapon, class);
	return MRES_Supercede;
}

static MRESReturn DHookCallback_CTFPlayer_GiveNamedItem_Pre(int player, DHookReturn ret, DHookParam params)
{
	if (g_bBypassGiveNamedItemHook)
		return MRES_Ignored;
	
	if (IsInWaitingForPlayers())
		return MRES_Ignored;
	
	if (params.IsNull(3))
		return MRES_Ignored;
	
	Address pScriptItem = params.GetAddress(3);
	
	// CEconItemView::m_iItemDefinitionIndex
	int iItemDefIndex = LoadFromAddress(pScriptItem + view_as<Address>(0x4), NumberType_Int16);
	TFClassType nClass = TF2_GetPlayerClass(player);
	int iLoadoutSlot = TF2Econ_GetItemLoadoutSlot(iItemDefIndex, nClass);
	
	if (iLoadoutSlot <= LOADOUT_POSITION_PDA2)
	{
		// Let Engineer keep his toolbox
		if (iLoadoutSlot == LOADOUT_POSITION_BUILDING && nClass == TFClass_Engineer)
			return MRES_Ignored;
		
		// Remove everything else
		ret.Value = -1;
		return MRES_Supercede;
	}
	
	return MRES_Ignored;
}
