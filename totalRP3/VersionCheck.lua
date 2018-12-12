----------------------------------------------------------------------------------
--- Total RP 3
---
--- This file does a couple of checks to make sure the add-on is being loaded properly in the expected environment.
--- ---------------------------------------------------------------------------
--- Copyright 2018 Renaud "Ellypse" Parize <ellypse@totalrp3.info> @EllypseCelwe
---
--- Licensed under the Apache License, Version 2.0 (the "License");
--- you may not use this file except in compliance with the License.
--- You may obtain a copy of the License at
---
---     http://www.apache.org/licenses/LICENSE-2.0
---
--- Unless required by applicable law or agreed to in writing, software
--- distributed under the License is distributed on an "AS IS" BASIS,
--- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--- See the License for the specific language governing permissions and
--- limitations under the License.
----------------------------------------------------------------------------------

--region Build version check
if TRP3_API.BUILD_NUMBER == nil then
	TRP3_API = nil -- Force API reference to nil. This will break most of the add-on so it stops loading.
	error([[Missing critical Total RP 3 files.

You probably tried to update the add-on while the game client was running. This is not recommended.
Please quit the game completely in order for the add-on to properly update.
]]);
end
--endregion

--region Game version check
local SUPPORTED_API_VERSION = 80000;
local SUPPORTED_BUILD = ("8.0 (API %s)"):format(SUPPORTED_API_VERSION);

local displayBuild, _, _, interfaceVersionNumber = GetBuildInfo();

if interfaceVersionNumber < SUPPORTED_API_VERSION then
	local currentBuild = ("%s (API %s)"):format(displayBuild, interfaceVersionNumber);
	error(([[This version of Total RP 3 only supports patch %s or above, but you are running patch %s.

Please downgrade to the latest version available for this patch.
If you are using the Twitch client, make sure to set your release type preferences to Release instead of Beta/Alpha to avoid getting preview versions.]])
		:format(SUPPORTED_BUILD, currentBuild));
end
--endregion

--region Dev builds setup
--@alpha@
-- Force showing Lua errors on non release builds
SetCVar("scriptErrors", 1);
--@end-alpha@
--endregion
