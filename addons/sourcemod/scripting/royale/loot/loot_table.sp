enum struct LootTable
{
	LootType type;
	Function callback_create;
	Function callback_class;
	Function callback_precache;
	CallbackParams callbackParams;
}

static ArrayList g_LootTableClass[view_as<int>(LootType)][view_as<int>(TFClassType)];
static ArrayList g_LootTableGlobal[view_as<int>(LootType)];

void LootTable_ReadConfig(KeyValues kv)
{
	//Clear current table
	for (int type = 0; type < sizeof(g_LootTableClass); type++)
		for (int class = 0; class < sizeof(g_LootTableClass[]); class++)
			delete g_LootTableClass[type][class];
	
	for (int type = 0; type < sizeof(g_LootTableGlobal); type++)
		delete g_LootTableGlobal[type];
	
	if (kv.GotoFirstSubKey(false))
	{
		do
		{
			LootTable lootTable;
			char type[CONFIG_MAXCHAR];
			kv.GetString("type", type, sizeof(type));
			lootTable.type = Loot_StrToLootType(type);
			
			char callback[CONFIG_MAXCHAR];
			kv.GetString("callback_create", callback, sizeof(callback), NULL_STRING);
			lootTable.callback_create = GetFunctionByName(null, callback);
			if (lootTable.callback_create == INVALID_FUNCTION)
			{
				LogError("Unable to find create function '%s' from type '%s'", callback, type);
				continue;
			}
			
			kv.GetString("callback_class", callback, sizeof(callback), NULL_STRING);
			if (callback[0] == '\0')
			{
				lootTable.callback_class = INVALID_FUNCTION;
			}
			else
			{
				lootTable.callback_class = GetFunctionByName(null, callback);
				if (lootTable.callback_class == INVALID_FUNCTION)
				{
					LogError("Unable to find class function '%s' from type '%s'", callback, type);
					continue;
				}
			}
				
			kv.GetString("callback_precache", callback, sizeof(callback), NULL_STRING);
			if (callback[0] == '\0')
			{
				lootTable.callback_precache = INVALID_FUNCTION;
			}
			else
			{
				lootTable.callback_precache = GetFunctionByName(null, callback);
				if (lootTable.callback_precache == INVALID_FUNCTION)
				{
					LogError("Unable to find precache function '%s' from type '%s'", callback, type);
					continue;
				}
			}
			
			if (kv.JumpToKey("params", false))
			{
				lootTable.callbackParams = new CallbackParams();
				lootTable.callbackParams.ReadConfig(kv);
			}
			
			//Call precache function
			if (lootTable.callback_precache != INVALID_FUNCTION)
			{
				Call_StartFunction(null, lootTable.callback_precache);
				Call_PushCell(lootTable.callbackParams);
				Call_Finish();
			}
			
			//Call class function, see which class this is for
			if (lootTable.callback_class == INVALID_FUNCTION)
			{
				if (!g_LootTableClass[lootTable.type][TFClass_Unknown])
					g_LootTableClass[lootTable.type][0] = new ArrayList(sizeof(LootTable));
				
				ArrayList list = g_LootTableClass[lootTable.type][0];
				list.PushArray(lootTable);
			}
			else
			{
				for (TFClassType class = TFClass_Scout; class <= TFClass_Engineer; class++)
				{
					Call_StartFunction(null, lootTable.callback_class);
					Call_PushCell(lootTable.callbackParams);
					Call_PushCell(class);
					
					bool result;
					if (Call_Finish(result) == SP_ERROR_NONE && result)
					{
						if (!g_LootTableClass[lootTable.type][class])
							g_LootTableClass[lootTable.type][class] = new ArrayList(sizeof(LootTable));
						
						ArrayList list = g_LootTableClass[lootTable.type][class];
						list.PushArray(lootTable);
					}
				}
			}
			
			if (!g_LootTableGlobal[lootTable.type])
				g_LootTableGlobal[lootTable.type] = new ArrayList(sizeof(LootTable));
			
			g_LootTableGlobal[lootTable.type].PushArray(lootTable);
		}
		while (kv.GotoNextKey(false));
		kv.GoBack();
	}
	kv.GoBack();
}

bool LootTable_GetRandomLoot(LootTable lootTable, LootType type, TFClassType class)
{
	ArrayList list;
	
	if (fr_classfilter.BoolValue)
	{
		if (g_LootTableClass[type][class])
			list = g_LootTableClass[type][class];
		else if (g_LootTableClass[type][TFClass_Unknown])
			list = g_LootTableClass[type][0];
		else
			return false;
	}
	else
	{
		if (g_LootTableGlobal[type])
			list = g_LootTableGlobal[type];
		else
			return false;
	}
	
	list.GetArray(GetRandomInt(0, list.Length - 1), lootTable, sizeof(lootTable));
	return true;
}