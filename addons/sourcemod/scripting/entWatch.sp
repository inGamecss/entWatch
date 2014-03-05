//====================================================================================================
//
// Name: entWatch
// Author: Prometheum & zaCade
// Description: Monitor entity interactions.
//
//====================================================================================================
#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <clientprefs>
#tryinclude <morecolors>
#tryinclude <entWatch>

//----------------------------------------------------------------------------------------------------
// Purpose: Entity Data
//----------------------------------------------------------------------------------------------------
enum entities
{
	String:ent_name[32],
	String:ent_shortname[32],
	String:ent_color[32],
	String:ent_buttonclass[32],
	String:ent_filtername[32],
	bool:ent_hasfiltername,
	bool:ent_blockpickup,
	bool:ent_allowtransfer,
	bool:ent_forcedrop,
	bool:ent_chat,
	bool:ent_hud,
	ent_hammerid,
	ent_weaponid,
	ent_buttonid,
	ent_ownerid,
	ent_mode, // 0 = No button, 1 = Spam protection only, 2 = Cooldowns, 3 = Limited uses, 4 = Limited uses with cooldowns
	ent_uses,
	ent_maxuses,
	ent_cooldown,
	ent_cooldowncount,
};

new entArray[512][entities];
new entArraySize = 512;

//----------------------------------------------------------------------------------------------------
// Purpose: Color Settings
//----------------------------------------------------------------------------------------------------
new String:color_tag[16] 			= "E01B5D";
new String:color_name[16] 			= "EDEDED";
new String:color_steamid[16] 		= "B2B2B2";
new String:color_use[16] 			= "67ADDF";
new String:color_pickup[16] 		= "C9EF66";
new String:color_drop[16] 			= "E562BA";
new String:color_disconnect[16] 	= "F1B567";
new String:color_death[16] 			= "F1B567";
new String:color_warning[16] 		= "F16767";

//----------------------------------------------------------------------------------------------------
// Purpose: Client Settings
//----------------------------------------------------------------------------------------------------
new Handle:G_hCookie_EnableDisplay = INVALID_HANDLE;
new Handle:G_hCookie_Restricted = INVALID_HANDLE;

new bool:G_bEnableDisplay[MAXPLAYERS + 1] = false;
new bool:G_bRestricted[MAXPLAYERS + 1] = false;

//----------------------------------------------------------------------------------------------------
// Purpose: Plugin Settings
//----------------------------------------------------------------------------------------------------
new Handle:G_hCvar_EnableDisplay = INVALID_HANDLE;
new Handle:G_hCvar_ConfigName = INVALID_HANDLE;

new bool:G_bRoundTransition = false;
new bool:G_bConfigLoaded = false;

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Plugin:myinfo =
{
	name 			= "entWatch",
	author 			= "Prometheum & zaCade",
	description 	= "Notify players about entity interactions.",
	version 		= "3.0",
	url 			= "https://github.com/Prometheum/entWatch"
};

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public OnPluginStart()
{
	G_hCvar_EnableDisplay = CreateConVar("entwatch_enabledisplay", "1", "Allow players to display the hud.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	G_hCvar_ConfigName = CreateConVar("entwatch_configname", "color_classic", "The name of the color config.", FCVAR_PLUGIN);
	
	G_hCookie_EnableDisplay = RegClientCookie("entwatch_enabledisplay", "", CookieAccess_Private);
	G_hCookie_Restricted = RegClientCookie("entwatch_restricted", "", CookieAccess_Private);
	
	RegConsoleCmd("sm_hud", Command_ToggleHUD);
	RegConsoleCmd("sm_status", Command_Status);
	
	RegAdminCmd("sm_eban", Command_Restrict, ADMFLAG_BAN);
	RegAdminCmd("sm_eunban", Command_Unrestrict, ADMFLAG_BAN);
	RegAdminCmd("sm_etransfer", Command_Transfer, ADMFLAG_BAN);
	RegAdminCmd("sm_erename", Command_Rename, ADMFLAG_BAN);
	RegAdminCmd("sm_efind", Command_Find, ADMFLAG_BAN);
	
	HookEvent("round_start", Event_RoundStart, EventHookMode_Pre);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_Pre);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	
	CreateTimer(1.0, Timer_DisplayHUD, _, TIMER_REPEAT);
	CreateTimer(1.0, Timer_Cooldowns, _, TIMER_REPEAT);
	
	LoadTranslations("entWatch.phrases");
	LoadTranslations("common.phrases");
	
	AutoExecConfig(true, "plugin.entWatch");
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public OnMapStart()
{
	for (new index = 0; index < entArraySize; index++)
	{
		Format(entArray[index][ent_name], 			32, "");
		Format(entArray[index][ent_shortname], 		32, "");
		Format(entArray[index][ent_color], 			32, "");
		Format(entArray[index][ent_buttonclass], 	32, "");
		Format(entArray[index][ent_filtername], 	32, "");
		entArray[index][ent_hasfiltername] 	= false;
		entArray[index][ent_blockpickup] 	= false;
		entArray[index][ent_allowtransfer] 	= false;
		entArray[index][ent_forcedrop] 		= false;
		entArray[index][ent_chat] 			= false;
		entArray[index][ent_hud] 			= false;
		entArray[index][ent_hammerid] 		= -1;
		entArray[index][ent_weaponid] 		= -1;
		entArray[index][ent_buttonid] 		= -1;
		entArray[index][ent_ownerid] 		= -1;
		entArray[index][ent_mode] 			= 0;
		entArray[index][ent_uses] 			= 0;
		entArray[index][ent_maxuses] 		= 0;
		entArray[index][ent_cooldown] 		= 0;
		entArray[index][ent_cooldowncount] 	= -1;
	}
	
	LoadColors();
	LoadConfig();
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action:Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (G_bConfigLoaded && G_bRoundTransition)
	{
		CPrintToChatAll("\x07%s[entWatch] \x07%s%t", color_tag, color_warning, "welcome");
	}
	
	G_bRoundTransition = false;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action:Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{	
	if (G_bConfigLoaded && !G_bRoundTransition)
	{
		for (new index = 0; index < entArraySize; index++)
		{
			SDKUnhook(entArray[index][ent_buttonid], SDKHook_Use, OnButtonUse);
			entArray[index][ent_weaponid] 		= -1;
			entArray[index][ent_buttonid] 		= -1;
			entArray[index][ent_ownerid] 		= -1;
			entArray[index][ent_uses] 			= 0;
			entArray[index][ent_cooldowncount] 	= -1;
		}
	}
	
	G_bRoundTransition = true;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public OnClientCookiesCached(client)
{
	new String:buffer_cookie[32];
	GetClientCookie(client, G_hCookie_EnableDisplay, buffer_cookie, sizeof(buffer_cookie));
	G_bEnableDisplay[client] = bool:StringToInt(buffer_cookie);
	
	GetClientCookie(client, G_hCookie_Restricted, buffer_cookie, sizeof(buffer_cookie));
	G_bRestricted[client] = bool:StringToInt(buffer_cookie);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_WeaponDropPost, OnWeaponDrop);
	SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquip);
	SDKHook(client, SDKHook_WeaponCanUse, OnWeaponCanUse);
	
	if (!AreClientCookiesCached(client))
	{
		G_bEnableDisplay[client] = false;
		G_bRestricted[client] = false;
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public OnClientDisconnect(client)
{
	if (G_bConfigLoaded && !G_bRoundTransition)
	{
		for (new index = 0; index < entArraySize; index++)
		{
			if (entArray[index][ent_ownerid] != -1)
			{
				if (entArray[index][ent_ownerid] == client)
				{
					entArray[index][ent_ownerid] = -1;
					
					if (entArray[index][ent_forcedrop] && IsValidEdict(entArray[index][ent_weaponid]))
						SDKHooks_DropWeapon(client, entArray[index][ent_weaponid]);
					
					if (entArray[index][ent_chat])
					{
						new String:buffer_steamid[32];
						GetClientAuthString(client, buffer_steamid, sizeof(buffer_steamid));
						ReplaceString(buffer_steamid, sizeof(buffer_steamid), "STEAM_", "", true);
						
						CPrintToChatAll("\x07%s[entWatch] \x07%s%N \x07%s(\x07%s%s\x07%s) \x07%s%t \x07%s%s", color_tag, color_name, client, color_disconnect, color_steamid, buffer_steamid, color_disconnect, color_disconnect, "disconnect", entArray[index][ent_color], entArray[index][ent_name]);
					}
				}
			}
		}
	}
	
	SDKUnhook(client, SDKHook_WeaponDropPost, OnWeaponDrop);
	SDKUnhook(client, SDKHook_WeaponEquipPost, OnWeaponEquip);
	SDKUnhook(client, SDKHook_WeaponCanUse, OnWeaponCanUse);
	
	G_bEnableDisplay[client] = false;
	G_bRestricted[client] = false;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (G_bConfigLoaded && !G_bRoundTransition)
	{
		for (new index = 0; index < entArraySize; index++)
		{
			if (entArray[index][ent_ownerid] != -1)
			{
				if (entArray[index][ent_ownerid] == client)
				{
					entArray[index][ent_ownerid] = -1;
					
					if (entArray[index][ent_forcedrop] && IsValidEdict(entArray[index][ent_weaponid]))
						SDKHooks_DropWeapon(client, entArray[index][ent_weaponid]);
					
					if (entArray[index][ent_chat])
					{
						new String:buffer_steamid[32];
						GetClientAuthString(client, buffer_steamid, sizeof(buffer_steamid));
						ReplaceString(buffer_steamid, sizeof(buffer_steamid), "STEAM_", "", true);
						
						CPrintToChatAll("\x07%s[entWatch] \x07%s%N \x07%s(\x07%s%s\x07%s) \x07%s%t \x07%s%s", color_tag, color_name, client, color_death, color_steamid, buffer_steamid, color_death, color_death, "death", entArray[index][ent_color], entArray[index][ent_name]);
					}
				}
			}
		}
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action:OnWeaponEquip(client, weapon)
{
	if (G_bConfigLoaded && !G_bRoundTransition && IsValidEdict(weapon))
	{
		for (new index = 0; index < entArraySize; index++)
		{
			if (entArray[index][ent_hammerid] == Entity_GetHammerID(weapon))
			{
				if (entArray[index][ent_weaponid] != -1)
				{
					if (entArray[index][ent_weaponid] == weapon)
					{
						entArray[index][ent_ownerid] = client;
						
						if (entArray[index][ent_chat])
						{
							new String:buffer_steamid[32];
							GetClientAuthString(client, buffer_steamid, sizeof(buffer_steamid));
							ReplaceString(buffer_steamid, sizeof(buffer_steamid), "STEAM_", "", true);
							
							CPrintToChatAll("\x07%s[entWatch] \x07%s%N \x07%s(\x07%s%s\x07%s) \x07%s%t \x07%s%s", color_tag, color_name, client, color_pickup, color_steamid, buffer_steamid, color_pickup, color_pickup, "pickup", entArray[index][ent_color], entArray[index][ent_name]);
						}
						
						break;
					}
				}
			}
		}
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action:OnWeaponDrop(client, weapon)
{
	if (G_bConfigLoaded && !G_bRoundTransition && IsValidEdict(weapon))
	{
		for (new index = 0; index < entArraySize; index++)
		{
			if (entArray[index][ent_hammerid] == Entity_GetHammerID(weapon))
			{
				if (entArray[index][ent_weaponid] != -1)
				{
					if (entArray[index][ent_weaponid] == weapon)
					{
						entArray[index][ent_ownerid] = -1;
						
						if (entArray[index][ent_chat])
						{
							new String:buffer_steamid[32];
							GetClientAuthString(client, buffer_steamid, sizeof(buffer_steamid));
							ReplaceString(buffer_steamid, sizeof(buffer_steamid), "STEAM_", "", true);
							
							CPrintToChatAll("\x07%s[entWatch] \x07%s%N \x07%s(\x07%s%s\x07%s) \x07%s%t \x07%s%s", color_tag, color_name, client, color_drop, color_steamid, buffer_steamid, color_drop, color_drop, "drop", entArray[index][ent_color], entArray[index][ent_name]);
						}
						
						break;
					}
				}
			}
		}
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action:OnWeaponCanUse(client, weapon)
{
	if (G_bConfigLoaded && !G_bRoundTransition && IsValidEdict(weapon))
	{
		for (new index = 0; index < entArraySize; index++)
		{
			if (entArray[index][ent_hammerid] == Entity_GetHammerID(weapon))
			{
				if (entArray[index][ent_weaponid] == -1)
				{
					entArray[index][ent_weaponid] = weapon;
					
					if (entArray[index][ent_buttonid] == -1 && entArray[index][ent_mode] != 0)
					{
						new button = -1;
						new String:buffer_targetname[32];
						new String:buffer_parentname[32];
						
						Entity_GetTargetName(weapon, buffer_targetname, sizeof(buffer_targetname));
						
						while ((button = FindEntityByClassname(button, entArray[index][ent_buttonclass])) != -1)
						{
							if (IsValidEdict(button))
							{
								Entity_GetParentName(button, buffer_parentname, sizeof(buffer_parentname));
								
								if (StrEqual(buffer_targetname, buffer_parentname))
								{
									SDKHook(button, SDKHook_Use, OnButtonUse);
									entArray[index][ent_buttonid] = button;
									break;
								}
							}
						}
					}
				}
				
				if (entArray[index][ent_weaponid] == weapon)
				{
					if (entArray[index][ent_blockpickup])
						return Plugin_Handled;
					
					if (G_bRestricted[client])
						return Plugin_Handled;
					
					return Plugin_Continue;
				}
			}
		}
	}
	
	return Plugin_Continue;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action:OnButtonUse(button, activator, caller, UseType:type, Float:value)
{
	if (G_bConfigLoaded && !G_bRoundTransition && IsValidEdict(button))
	{
		for (new index = 0; index < entArraySize; index++)
		{
			if (entArray[index][ent_buttonid] != -1)
			{
				if (entArray[index][ent_buttonid] == button)
				{
					if (entArray[index][ent_ownerid] != activator && entArray[index][ent_ownerid] != caller)
						return Plugin_Handled;
					
					if (entArray[index][ent_hasfiltername])
						DispatchKeyValue(activator, "targetname", entArray[index][ent_filtername]);
					
					new String:buffer_steamid[32];
					GetClientAuthString(activator, buffer_steamid, sizeof(buffer_steamid));
					ReplaceString(buffer_steamid, sizeof(buffer_steamid), "STEAM_", "", true);
					
					if (entArray[index][ent_mode] == 1)
					{
						return Plugin_Changed;
					}
					else if (entArray[index][ent_mode] == 2 && entArray[index][ent_cooldowncount] <= -1)
					{
						CPrintToChatAll("\x07%s[entWatch] \x07%s%N \x07%s(\x07%s%s\x07%s) \x07%s%t \x07%s%s", color_tag, color_name, activator, color_use, color_steamid, buffer_steamid, color_use, color_use, "use", entArray[index][ent_color], entArray[index][ent_name]);
						entArray[index][ent_cooldowncount] = entArray[index][ent_cooldown];
						return Plugin_Changed;
					}
					else if (entArray[index][ent_mode] == 3 && entArray[index][ent_uses] < entArray[index][ent_maxuses])
					{
						CPrintToChatAll("\x07%s[entWatch] \x07%s%N \x07%s(\x07%s%s\x07%s) \x07%s%t \x07%s%s", color_tag, color_name, activator, color_use, color_steamid, buffer_steamid, color_use, color_use, "use", entArray[index][ent_color], entArray[index][ent_name]);
						entArray[index][ent_uses]++;
						return Plugin_Changed;
					}
					else if (entArray[index][ent_mode] == 4 && entArray[index][ent_uses] < entArray[index][ent_maxuses] && entArray[index][ent_cooldowncount] <= -1)
					{
						CPrintToChatAll("\x07%s[entWatch] \x07%s%N \x07%s(\x07%s%s\x07%s) \x07%s%t \x07%s%s", color_tag, color_name, activator, color_use, color_steamid, buffer_steamid, color_use, color_use, "use", entArray[index][ent_color], entArray[index][ent_name]);
						entArray[index][ent_cooldowncount] = entArray[index][ent_cooldown];
						entArray[index][ent_uses]++;
						return Plugin_Changed;
					}
					
					return Plugin_Handled;
				}
			}
		}
	}
	
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action:Timer_DisplayHUD(Handle:timer)
{
	if (GetConVarBool(G_hCvar_EnableDisplay))
	{
		if (G_bConfigLoaded && !G_bRoundTransition)
		{
			new String:buffer_text[250];
			
			for (new index = 0; index < entArraySize; index++)
			{
				new String:buffer_temp[128];
				
				if (entArray[index][ent_hud] && entArray[index][ent_ownerid] != -1)
				{
					if (entArray[index][ent_mode] == 2)
					{
						if (entArray[index][ent_cooldowncount] > 0)
						{
							Format(buffer_temp, sizeof(buffer_temp), "%s[%d]: %N\n", entArray[index][ent_shortname], entArray[index][ent_cooldowncount], entArray[index][ent_ownerid]);
						}
						else
						{
							Format(buffer_temp, sizeof(buffer_temp), "%s[%s]: %N\n", entArray[index][ent_shortname], "R", entArray[index][ent_ownerid]);
						}
					}
					else if (entArray[index][ent_mode] == 3)
					{
						if (entArray[index][ent_uses] < entArray[index][ent_maxuses])
						{
							Format(buffer_temp, sizeof(buffer_temp), "%s[%d/%d]: %N\n", entArray[index][ent_shortname], entArray[index][ent_uses], entArray[index][ent_maxuses], entArray[index][ent_ownerid]);
						}
						else
						{
							Format(buffer_temp, sizeof(buffer_temp), "%s[%s]: %N\n", entArray[index][ent_shortname], "D", entArray[index][ent_ownerid]);
						}
					}
					else if (entArray[index][ent_mode] == 4)
					{
						if (entArray[index][ent_cooldowncount] > 0)
						{
							Format(buffer_temp, sizeof(buffer_temp), "%s[%d]: %N\n", entArray[index][ent_shortname], entArray[index][ent_cooldowncount], entArray[index][ent_ownerid]);
						}
						else
						{
							if (entArray[index][ent_uses] < entArray[index][ent_maxuses])
							{
								Format(buffer_temp, sizeof(buffer_temp), "%s[%d/%d]: %N\n", entArray[index][ent_shortname], entArray[index][ent_uses], entArray[index][ent_maxuses], entArray[index][ent_ownerid]);
							}
							else
							{
								Format(buffer_temp, sizeof(buffer_temp), "%s[%s]: %N\n", entArray[index][ent_shortname], "D", entArray[index][ent_ownerid]);
							}
						}
					}
					else
					{
						Format(buffer_temp, sizeof(buffer_temp), "%s[%s]: %N\n", entArray[index][ent_shortname], "N/A", entArray[index][ent_ownerid]);
					}
				}
				
				if (strlen(buffer_temp) + strlen(buffer_text) <= sizeof(buffer_text))
				{
					StrCat(buffer_text, sizeof(buffer_text), buffer_temp);
				}
			}
			
			for (new ply = 1; ply <= MaxClients; ply++)
			{
				if (IsClientConnected(ply) && IsClientInGame(ply))
				{
					if (G_bEnableDisplay[ply])
					{
						new Handle:hBuffer = StartMessageOne("KeyHintText", ply);
						BfWriteByte(hBuffer, 1);
						BfWriteString(hBuffer, buffer_text);
						EndMessage();
					}
				}
			}
		}
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action:Timer_Cooldowns(Handle:timer)
{
	if (G_bConfigLoaded && !G_bRoundTransition)
	{
		for (new index = 0; index < entArraySize; index++)
		{
			if (entArray[index][ent_cooldowncount] >= 0)
			{
				entArray[index][ent_cooldowncount]--;
			}
		}
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action:Command_ToggleHUD(client, args)
{
	if (AreClientCookiesCached(client))
	{
		if (G_bEnableDisplay[client])
		{
			CReplyToCommand(client, "\x07%s[entWatch] \x07%s%t", color_tag, color_warning, "hud disabled");
			SetClientCookie(client, G_hCookie_EnableDisplay, "0");
			G_bEnableDisplay[client] = false;
		}
		else
		{
			CReplyToCommand(client, "\x07%s[entWatch] \x07%s%t", color_tag, color_warning, "hud enabled");
			SetClientCookie(client, G_hCookie_EnableDisplay, "1");
			G_bEnableDisplay[client] = true;
		}
	}
	else
	{
		CReplyToCommand(client, "\x07%s[entWatch] \x07%s%t", color_tag, color_warning, "cookies loading");
	}
	
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action:Command_Status(client, args)
{
	if (AreClientCookiesCached(client))
	{
		if (G_bRestricted[client])
		{
			CReplyToCommand(client, "\x07%s[entWatch] \x07%s%t", color_tag, color_warning, "you are restricted");
		}
		else
		{
			CReplyToCommand(client, "\x07%s[entWatch] \x07%s%t", color_tag, color_warning, "you are not restricted");
		}
	}
	else
	{
		CReplyToCommand(client, "\x07%s[entWatch] \x07%s%t", color_tag, color_warning, "cookies loading");
	}
	
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action:Command_Restrict(client, args)
{
	if (GetCmdArgs() < 1)
	{
		CReplyToCommand(client, "\x07%s[entWatch] \x07%sUsage: sm_eban <target>", color_tag, color_warning);
		return Plugin_Handled;
	}
	
	new String:target_argument[64];
	GetCmdArg(1, target_argument, sizeof(target_argument));
	
	new target = FindTarget(client, target_argument, true);
	
	if (target == -1)
		return Plugin_Handled;
	
	G_bRestricted[target] = true;
	SetClientCookie(target, G_hCookie_Restricted, "1");
	
	CPrintToChatAll("\x07%s[entWatch] \x07%s%N \x07%srestricted \x07%s%N", color_tag, color_name, client, color_warning, color_name, target);
	LogAction(client, -1, "%L restricted %L", client, target);
	
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action:Command_Unrestrict(client, args)
{
	if (GetCmdArgs() < 1)
	{
		CReplyToCommand(client, "\x07%s[entWatch] \x07%sUsage: sm_eunban <target>", color_tag, color_warning);
		return Plugin_Handled;
	}
	
	new String:target_argument[64];
	GetCmdArg(1, target_argument, sizeof(target_argument));
	
	new target = FindTarget(client, target_argument, true);
	
	if (target == -1)
		return Plugin_Handled;
	
	G_bRestricted[target] = false;
	SetClientCookie(target, G_hCookie_Restricted, "0");
	
	CPrintToChatAll("\x07%s[entWatch] \x07%s%N \x07%sunrestricted \x07%s%N", color_tag, color_name, client, color_warning, color_name, target);
	LogAction(client, -1, "%L unrestricted %L", client, target);
	
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action:Command_Transfer(client, args)
{
	if (GetCmdArgs() < 2)
	{
		CReplyToCommand(client, "\x07%s[entWatch] \x07%sUsage: sm_etransfer <owner> <reciever>", color_tag, color_warning);
		return Plugin_Handled;
	}
	
	new String:target_argument[64];
	GetCmdArg(1, target_argument, sizeof(target_argument));
	
	new target = FindTarget(client, target_argument, true);
	
	if (target == -1)
		return Plugin_Handled;
	
	new String:reciever_argument[64];
	GetCmdArg(2, reciever_argument, sizeof(reciever_argument));
	
	new reciever = FindTarget(client, reciever_argument, true);
	
	if (reciever == -1)
		return Plugin_Handled;
	
	if (G_bConfigLoaded && !G_bRoundTransition)
	{
		for (new index = 0; index < entArraySize; index++)
		{
			if (entArray[index][ent_ownerid] != -1)
			{
				if (entArray[index][ent_ownerid] == target)
				{
					if (entArray[index][ent_allowtransfer])
					{
						if (IsValidEdict(entArray[index][ent_weaponid]))
						{
							new String:buffer_classname[64];
							GetEdictClassname(entArray[index][ent_weaponid], buffer_classname, sizeof(buffer_classname));
							
							SDKHooks_DropWeapon(target, entArray[index][ent_weaponid]);
							GivePlayerItem(target, buffer_classname);
							
							if (entArray[index][ent_chat])
							{
								entArray[index][ent_chat] = false;
								EquipPlayerWeapon(reciever, entArray[index][ent_weaponid]);
								entArray[index][ent_chat] = true;
							}
							else
							{
								EquipPlayerWeapon(reciever, entArray[index][ent_weaponid]);
							}
						}
					}
				}
			}
		}
	}
	
	CPrintToChatAll("\x07%s[entWatch] \x07%s%N \x07%stransfered all items from \x07%s%N \x07%sto \x07%s%N", color_tag, color_name, client, color_warning, color_name, target, color_warning, color_name, reciever);
	LogAction(client, -1, "%L transfered all items from %L to %L", client, target, reciever);
	
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action:Command_Rename(client, args)
{
	if (GetCmdArgs() < 2)
	{
		CReplyToCommand(client, "\x07%s[entWatch] \x07%sUsage: sm_erename <target> <name>", color_tag, color_warning);
		return Plugin_Handled;
	}
	
	new String:target_argument[64];
	GetCmdArg(1, target_argument, sizeof(target_argument));
	
	new target = FindTarget(client, target_argument, true);
	
	if (target == -1)
		return Plugin_Handled;
	
	new String:name_argument[64];
	GetCmdArg(2, name_argument, sizeof(name_argument));
	
	DispatchKeyValue(target, "targetname", name_argument);
	LogAction(client, -1, "%L has renamed %L to \"%s\"", client, target, name_argument);
	
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Action:Command_Find(client, args)
{
	if (GetCmdArgs() < 1)
	{
		CReplyToCommand(client, "\x07%s[entWatch] \x07%sUsage: sm_efind <classname>", color_tag, color_warning);
		return Plugin_Handled;
	}
	
	new String:name_argument[64];
	GetCmdArg(1, name_argument, sizeof(name_argument));
	
	new weapon = -1;
	new String:buffer_targetname[32];
	
	while ((weapon = FindEntityByClassname(weapon, name_argument)) != -1)
	{
		if (IsValidEdict(weapon))
		{
			Entity_GetTargetName(weapon, buffer_targetname, sizeof(buffer_targetname));
			PrintToConsole(client, "-> Classname: %s -> HammerID: %i -> Targetname: %s", name_argument, Entity_GetHammerID(weapon), buffer_targetname);
		}
	}
	
	CReplyToCommand(client, "\x07%s[entWatch] \x07%sDone finding all \"%s\" in the current map. A list has been printed in your console.", color_tag, color_warning, name_argument);
	LogAction(client, -1, "%L has used the entity finder to find all \"%s\" in the map.", client, name_argument);
	
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
stock LoadColors()
{
	new Handle:hKeyValues = CreateKeyValues("colors");
	new String:buffer_config[128];
	new String:buffer_path[PLATFORM_MAX_PATH];
	new String:buffer_temp[16];
	
	GetConVarString(G_hCvar_ConfigName, buffer_config, sizeof(buffer_config));
	Format(buffer_path, sizeof(buffer_path), "cfg/sourcemod/entwatch/colors/%s.cfg", buffer_config);
	FileToKeyValues(hKeyValues, buffer_path);
	
	KvRewind(hKeyValues);
	
	KvGetString(hKeyValues, "color_tag", buffer_temp, sizeof(buffer_temp));
	Format(color_tag, sizeof(color_tag), "%s", buffer_temp);
	
	KvGetString(hKeyValues, "color_name", buffer_temp, sizeof(buffer_temp));
	Format(color_name, sizeof(color_name), "%s", buffer_temp);
	
	KvGetString(hKeyValues, "color_steamid", buffer_temp, sizeof(buffer_temp));
	Format(color_steamid, sizeof(color_steamid), "%s", buffer_temp);
	
	KvGetString(hKeyValues, "color_use", buffer_temp, sizeof(buffer_temp));
	Format(color_use, sizeof(color_use), "%s", buffer_temp);
	
	KvGetString(hKeyValues, "color_pickup", buffer_temp, sizeof(buffer_temp));
	Format(color_pickup, sizeof(color_pickup), "%s", buffer_temp);
	
	KvGetString(hKeyValues, "color_drop", buffer_temp, sizeof(buffer_temp));
	Format(color_drop, sizeof(color_drop), "%s", buffer_temp);
	
	KvGetString(hKeyValues, "color_disconnect", buffer_temp, sizeof(buffer_temp));
	Format(color_disconnect, sizeof(color_disconnect), "%s", buffer_temp);
	
	KvGetString(hKeyValues, "color_death", buffer_temp, sizeof(buffer_temp));
	Format(color_death, sizeof(color_death), "%s", buffer_temp);
	
	KvGetString(hKeyValues, "color_warning", buffer_temp, sizeof(buffer_temp));
	Format(color_warning, sizeof(color_warning), "%s", buffer_temp);
	
	CloseHandle(hKeyValues);
}

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
stock LoadConfig()
{
	new Handle:hKeyValues = CreateKeyValues("entities");
	new String:buffer_map[128];
	new String:buffer_path[PLATFORM_MAX_PATH];
	new String:buffer_temp[32];
	new buffer_amount;
	
	GetCurrentMap(buffer_map, sizeof(buffer_map));
	Format(buffer_path, sizeof(buffer_path), "cfg/sourcemod/entwatch/maps/%s.cfg", buffer_map);
	FileToKeyValues(hKeyValues, buffer_path);
	
	LogMessage("Loading %s", buffer_path);
	
	KvRewind(hKeyValues);
	if (KvGotoFirstSubKey(hKeyValues))
	{
		G_bConfigLoaded = true;
		entArraySize = 0;
		
		do
		{
			KvGetString(hKeyValues, "maxamount", buffer_temp, sizeof(buffer_temp));
			buffer_amount = StringToInt(buffer_temp);
			
			for (new i = 0; i < buffer_amount; i++)
			{
				KvGetString(hKeyValues, "name", buffer_temp, sizeof(buffer_temp));
				Format(entArray[entArraySize][ent_name], 32, "%s", buffer_temp);
				
				KvGetString(hKeyValues, "shortname", buffer_temp, sizeof(buffer_temp));
				Format(entArray[entArraySize][ent_shortname], 32, "%s", buffer_temp);
				
				KvGetString(hKeyValues, "color", buffer_temp, sizeof(buffer_temp));
				Format(entArray[entArraySize][ent_color], 32, "%s", buffer_temp);
				
				KvGetString(hKeyValues, "buttonclass", buffer_temp, sizeof(buffer_temp));
				Format(entArray[entArraySize][ent_buttonclass], 32, "%s", buffer_temp);
				
				KvGetString(hKeyValues, "filtername", buffer_temp, sizeof(buffer_temp));
				Format(entArray[entArraySize][ent_filtername], 32, "%s", buffer_temp);
				
				KvGetString(hKeyValues, "hasfiltername", buffer_temp, sizeof(buffer_temp));
				entArray[entArraySize][ent_hasfiltername] = StrEqual(buffer_temp, "true", false);
				
				KvGetString(hKeyValues, "blockpickup", buffer_temp, sizeof(buffer_temp));
				entArray[entArraySize][ent_blockpickup] = StrEqual(buffer_temp, "true", false);
				
				KvGetString(hKeyValues, "allowtransfer", buffer_temp, sizeof(buffer_temp));
				entArray[entArraySize][ent_allowtransfer] = StrEqual(buffer_temp, "true", false);
				
				KvGetString(hKeyValues, "forcedrop", buffer_temp, sizeof(buffer_temp));
				entArray[entArraySize][ent_forcedrop] = StrEqual(buffer_temp, "true", false);
				
				KvGetString(hKeyValues, "chat", buffer_temp, sizeof(buffer_temp));
				entArray[entArraySize][ent_chat] = StrEqual(buffer_temp, "true", false);
				
				KvGetString(hKeyValues, "hud", buffer_temp, sizeof(buffer_temp));
				entArray[entArraySize][ent_hud] = StrEqual(buffer_temp, "true", false);
				
				KvGetString(hKeyValues, "hammerid", buffer_temp, sizeof(buffer_temp));
				entArray[entArraySize][ent_hammerid] = StringToInt(buffer_temp);
				
				KvGetString(hKeyValues, "mode", buffer_temp, sizeof(buffer_temp));
				entArray[entArraySize][ent_mode] = StringToInt(buffer_temp);
				
				KvGetString(hKeyValues, "maxuses", buffer_temp, sizeof(buffer_temp));
				entArray[entArraySize][ent_maxuses] = StringToInt(buffer_temp);
				
				KvGetString(hKeyValues, "cooldown", buffer_temp, sizeof(buffer_temp));
				entArray[entArraySize][ent_cooldown] = StringToInt(buffer_temp);
				
				entArraySize++;
			}
		}
		while (KvGotoNextKey(hKeyValues));
	}
	else
	{
		G_bConfigLoaded = false;
		
		LogMessage("Could not load %s", buffer_path);
	}
	
	CloseHandle(hKeyValues);
}