----------------------------------------------------------------------------------
-- Total RP 3
-- Broadcast communication system
--	---------------------------------------------------------------------------
--	Copyright 2014 Sylvain Cossement (telkostrasz@telkostrasz.be)
--
--	Licensed under the Apache License, Version 2.0 (the "License");
--	you may not use this file except in compliance with the License.
--	You may obtain a copy of the License at
--
--		http://www.apache.org/licenses/LICENSE-2.0
--
--	Unless required by applicable law or agreed to in writing, software
--	distributed under the License is distributed on an "AS IS" BASIS,
--	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--	See the License for the specific language governing permissions and
--	limitations under the License.
----------------------------------------------------------------------------------

-- imports
local GetChannelRosterInfo = GetChannelRosterInfo;
local GetChannelDisplayInfo = GetChannelDisplayInfo;
local GetChannelName = GetChannelName;
local JoinChannelByName = JoinChannelByName;
local RegisterAddonMessagePrefix = RegisterAddonMessagePrefix;
local wipe, string, pairs, strsplit, assert, tinsert, type, tostring = wipe, string, pairs, strsplit, assert, tinsert, type, tostring;
local time = time;
local ChatThrottleLib = ChatThrottleLib;
local Globals = TRP3_API.globals;
local Utils = TRP3_API.utils;
local Log = Utils.log;
local Comm, isIDIgnored = TRP3_API.communication, nil;
local unitIDToInfo = Utils.str.unitIDToInfo;
local getConfigValue = TRP3_API.configuration.getValue;
local loc = TRP3_API.locale.getText;

Comm.broadcast = {};
local ticker;

local function config_UseBroadcast()
	return getConfigValue("comm_broad_use");
end

local function config_BroadcastChannel()
	return getConfigValue("comm_broad_chan");
end

--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
-- Communication protocol
--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*

Comm.broadcast.HELLO_CMD = "TRP3HI";
local HELLO_CMD = Comm.broadcast.HELLO_CMD;

local helloWorlded = false;
local PREFIX_REGISTRATION, PREFIX_P2P_REGISTRATION = {}, {};
local BROADCAST_PREFIX = "RPB";
local BROADCAST_VERSION = 1;
local BROADCAST_SEPARATOR = "~";
local BROADCAST_HEADER = BROADCAST_PREFIX .. BROADCAST_VERSION;

local function broadcast(command, ...)
	if not config_UseBroadcast() or not command then
		Log.log("Bad params");
		return;
	end
	if not helloWorlded and command ~= HELLO_CMD then
		Log.log("Broadcast channel not yet initialized.");
		return;
	end
	local message = BROADCAST_HEADER .. BROADCAST_SEPARATOR .. command;
	for _, arg in pairs({...}) do
		arg = tostring(arg);
		if arg:find(BROADCAST_SEPARATOR) then
			Log.log("Trying a broadcast with a arg containing the separator character. Abord !", Log.level.WARNING);
			return;
		end
		message = message .. BROADCAST_SEPARATOR .. arg;
	end
	if message:len() < 254 then
		local channelName = GetChannelName(config_BroadcastChannel());
		ChatThrottleLib:SendAddonMessage("NORMAL", BROADCAST_HEADER, message, "CHANNEL", channelName);
	else
		Log.log(("Trying a broadcast with a message with lenght %s. Abord !"):format(message:len()), Log.level.WARNING);
	end
end
Comm.broadcast.broadcast = broadcast;

local function onBroadcastReceived(message, sender, channel)
	if not isIDIgnored(sender) and string.lower(channel) == string.lower(config_BroadcastChannel()) then
		local header, command, arg1, arg2, arg3, arg4, arg5, arg6, arg7 = strsplit(BROADCAST_SEPARATOR, message);
		if not header == BROADCAST_HEADER or not command then
			return; -- If not RP protocol or don't have a command
		end
		for _, callback in pairs(PREFIX_REGISTRATION[command] or Globals.empty) do
			callback(sender, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
		end
	end
end

-- Register a function to callback when receiving args to a certain command
function Comm.broadcast.registerCommand(command, callback)
	assert(command and callback and type(callback) == "function", "Usage: command, callback");
	if PREFIX_REGISTRATION[command] == nil then
		PREFIX_REGISTRATION[command] = {};
	end
	tinsert(PREFIX_REGISTRATION[command], callback);
end

--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
-- Peer to peer part
--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*

local function onP2PMessageReceived(message, sender)
	if not sender then
		Log.log("onP2PMessageReceived: Malformed senderID: " .. tostring(sender), Log.level.WARNING);
		return;
	end
	if not sender:find('-') then
		sender = Utils.str.unitInfoToID(sender);
	end
	if not isIDIgnored(sender) then
		local command, arg1, arg2, arg3, arg4, arg5, arg6, arg7 = strsplit(BROADCAST_SEPARATOR, message);
		if PREFIX_P2P_REGISTRATION[command] then
			for _, callback in pairs(PREFIX_P2P_REGISTRATION[command]) do
				callback(sender, arg1, arg2, arg3, arg4, arg5, arg6, arg7);
			end
		end
	end
end

-- Register a function to callback when receiving args to a certain command
function Comm.broadcast.registerP2PCommand(command, callback)
	assert(command and callback and type(callback) == "function", "Usage: command, callback");
	if PREFIX_P2P_REGISTRATION[command] == nil then
		PREFIX_P2P_REGISTRATION[command] = {};
	end
	tinsert(PREFIX_P2P_REGISTRATION[command], callback);
end

local function sendP2PMessage(target, command, ...)
	local message = command;
	for _, arg in pairs({...}) do
		arg = tostring(arg);
		if arg:find(BROADCAST_SEPARATOR) then
			Log.log("Trying a broadcast with a arg containing the separator character. Abord !", Log.level.WARNING);
			return;
		end
		message = message .. BROADCAST_SEPARATOR .. arg;
	end
	if message:len() < 254 then
		ChatThrottleLib:SendAddonMessage("NORMAL", BROADCAST_HEADER, message, "WHISPER", target);
	else
		Log.log(("Trying a P2P message with a message with lenght %s. Abord !"):format(message:len()), Log.level.WARNING);
	end
end
Comm.broadcast.sendP2PMessage = sendP2PMessage;

--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
-- Players connexions listener
--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*

local connectedPlayers = {};

Comm.broadcast.isPlayerBroadcastable = function(playerName)
	return connectedPlayers[playerName] ~= nil;
end

Comm.broadcast.getPlayers = function()
	return connectedPlayers;
end

Comm.broadcast.resetPlayers = function()
	if not config_UseBroadcast() then
		return nil;
	end
	local channelName;
	wipe(connectedPlayers);
	for i=1, MAX_CHANNEL_BUTTONS, 1 do
		channelName = GetChannelDisplayInfo(i);
		if channelName == config_BroadcastChannel() then
			local j = 1;
			while GetChannelRosterInfo(i, j) do
				local playerName = GetChannelRosterInfo(i, j);
				connectedPlayers[playerName] = 1;
				j = j + 1;
			end
			break;
		end
	end
	return connectedPlayers;
end

local function onChannelJoin(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
	if config_UseBroadcast() and arg2 and arg9 == config_BroadcastChannel() then
		local unitName = unitIDToInfo(arg2);
		connectedPlayers[unitName] = 1;
	end
end

local function onChannelLeave(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
	if config_UseBroadcast() and arg2 and arg9 == config_BroadcastChannel() then
		local unitName = unitIDToInfo(arg2);
		connectedPlayers[unitName] = nil;
	end
end

local function onMessageReceived(...)
	local prefix, message , distributionType, sender, _, _, _, channel = ...;
	if prefix == BROADCAST_HEADER then
		if distributionType == "CHANNEL" then
			onBroadcastReceived(message, sender, channel);
		else
			onP2PMessageReceived(message, sender);
		end
	end
end

--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
-- Init and helloWorld
--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*

Comm.broadcast.init = function()
	isIDIgnored = TRP3_API.register.isIDIgnored;

	-- First, register prefix
	Utils.event.registerHandler("PLAYER_ENTERING_WORLD", function()
		RegisterAddonMessagePrefix(BROADCAST_HEADER);
	end);

	-- Then, launch the loop
	TRP3_API.events.listenToEvent(TRP3_API.events.WORKFLOW_ON_LOADED, function()
		if config_UseBroadcast() then
			ticker = C_Timer.NewTicker(5, function(self)
				if GetChannelName(string.lower(config_BroadcastChannel())) == 0 then
					Log.log("Step 1: Try to connect to broadcast channel: " .. config_BroadcastChannel());
					JoinChannelByName(string.lower(config_BroadcastChannel()));
				else
					Log.log("Step 2: Connected to broadcast channel: " .. config_BroadcastChannel() .. ". Now sending HELLO command.");
					if not helloWorlded then
						broadcast(HELLO_CMD, Globals.version, Globals.version_display);
					end
				end
			end, 9);
		end
	end);

	-- When we receive a broadcast or a P2P response
	Utils.event.registerHandler("CHAT_MSG_ADDON", onMessageReceived);

	-- When someone placed a password on the channel
	Utils.event.registerHandler("CHANNEL_PASSWORD_REQUEST", function(channel)
		if channel == config_BroadcastChannel() then
			Log.log("Passworded !");
			Utils.message.displayMessage(loc("BROADCAST_PASSWORD"):format(channel));
			ticker:Cancel();
		end
	end);

	-- For when someone just places a password
	Utils.event.registerHandler("CHAT_MSG_CHANNEL_NOTICE_USER", function(mode, user, _, _, _, _, _, _, channel)
		if mode == "PASSWORD_CHANGED" and channel == config_BroadcastChannel() then
			Utils.message.displayMessage(loc("BROADCAST_PASSWORDED"):format(user, channel));
		end
	end);

	-- When you are already in 10 channel
	Utils.event.registerHandler("CHAT_MSG_SYSTEM", function(message)
		if config_UseBroadcast() and message == ERR_TOO_MANY_CHAT_CHANNELS and not helloWorlded then
			Utils.message.displayMessage(loc("BROADCAST_10"));
			ticker:Cancel();
		end
	end);

	-- For stats
	Utils.event.registerHandler("CHAT_MSG_CHANNEL_JOIN", onChannelJoin);
	Utils.event.registerHandler("CHAT_MSG_CHANNEL_LEAVE", onChannelLeave);

	-- We register our own HELLO msg so that when it happens we know we are capable of sending and receive on the channel.
	Comm.broadcast.registerCommand(HELLO_CMD, function(sender, command)
		if sender == Globals.player_id then
			Log.log("Step 3: HELLO command sent and parsed. Broadcast channel initialized.");
			helloWorlded = true;
			ticker:Cancel();
		end
	end);
end