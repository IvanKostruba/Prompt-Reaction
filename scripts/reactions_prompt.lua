function registerOptions()
	OptionsManager.registerOption2("REPRO_MSG_FORMAT", false, "option_header_REPRO", "option_label_REPRO_chat_output", "option_entry_cycler",
		{ labels = "option_val_npc_link|option_val_power_desc|option_val_off", values = "npc_ref|power_desc|off", baselabel = "option_val_power_link", baseval = "power_ref", default = "option_val_power_link" });
	OptionsManager.registerOption2("REPRO_REPORT_PARSING", false, "option_header_REPRO", "option_label_REPRO_report_parsing", "option_entry_cycler",
		{ labels = "option_val_on", values = "on", baselabel = "option_val_off", baseval = "off", default = "off" });
end

function onInit()
	registerOptions()

	CombatManager2.onNPCPostAddReProOrig = CombatManager2.onNPCPostAdd
	CombatManager2.onNPCPostAdd = postNPCAddDecorator
	-- have to re-register since we replaced the registered function
	CombatRecordManager.setRecordTypePostAddCallback("npc", CombatManager2.onNPCPostAdd);

	ActionAttack.applyAttackReProOrig = ActionAttack.applyAttack
	ActionAttack.applyAttack = applyAttackDecorator

	ActionDamage.applyDamageReProOrig = ActionDamage.applyDamage
	ActionDamage.applyDamage = applyDamageDecorator;
end

local ReactionOnSelf = {}
local ReactionOnOther = {}

function addReaction(aTable, sID, aReaction)
	if aTable[sID] == nil then aTable[sID] = {aReaction}
	else table.insert(aTable[sID], aReaction) end
end

function matchReaction(aFlags, aReaction)
	if next(aFlags) == nil then return false end
	for _, f in ipairs(aFlags) do
		Debug.console(f)
		Debug.console(aReaction.aTrigger[f])
		if aReaction.aTrigger[f] == nil then return false end
	end
	return true
end

function postNPCAddDecorator(tCustom)
	-- Call the original onPreAttackResolve function
	CombatManager2.onNPCPostAddReProOrig(tCustom)

	if not tCustom.nodeRecord or not tCustom.nodeCT then
		return;
	end
	local rActor = ActorManager.resolveActor(tCustom.nodeCT);
	local sCreatureType = DB.getValue(tCustom.nodeCT, "type", 0)
	Debug.console(tCustom.nodeRecord)
	Debug.console(tCustom.nodeCT)
	Debug.console(rActor)
	Debug.console(rActor.sName .. " " .. sCreatureType)
	aParsedName = parseName(rActor.sName)
	-- rActor.sType -- 'npc'
	reactorID = extractID(rActor)
	Debug.console(n)
	for _,v in ipairs(DB.getChildList(tCustom.nodeCT, "reactions")) do
		local sName = StringManager.trim(DB.getValue(v, "name", ""));
		local sDesc = StringManager.trim(DB.getValue(v, "desc", ""));
		r = parseReaction(sName:lower(), aParsedName, StringManager.parseWords(sDesc:lower()))
		Debug.console(r)
		if r.aTrigger ~= nil and next(r.aTrigger) ~= nil then
			r.vDBRecord = v
			if r.sTarget == "self" then
				addReaction(ReactionOnSelf, reactorID, r)
				sendParsingMessage(sName, r, false)
			else
				addReaction(ReactionOnOther, reactorID, r)
				sendParsingMessage(sName, r, true)
			end
		end
	end
	for _,v in ipairs(DB.getChildList(tCustom.nodeCT, "traits")) do
		local sName = StringManager.trim(DB.getValue(v, "name", ""));
		local sDesc = StringManager.trim(DB.getValue(v, "desc", ""));
		tr = parseTrait(sName:lower(), aParsedName, StringManager.parseWords(sDesc:lower()))
		if tr.aTrigger ~= nil and next(tr.aTrigger) ~= nil then
			tr.vDBRecord = v
			addReaction(ReactionOnSelf, reactorID, tr)
			sendParsingMessage(sName, tr, false)
		end
		Debug.console(tr)
	end
	Debug.console("-----SELF-----")
	Debug.console(ReactionOnSelf)
	Debug.console("-----OTHER-----")
	Debug.console(ReactionOnOther)
	DB.addHandler(tCustom.nodeCT, "onDelete", onCombatantDelete);
end

function extractID(rActor)
	local _,_,reactorID = string.find(rActor.sCTNode, "-(%d+)$")
	return reactorID
end

function onCombatantDelete(vNode)
	-- sName = DB.getValue(vNode, "name", "");  NPC name
	Debug.console(vNode)
	DB.removeHandler(vNode, "onDelete", onCombatantDelete);
	local rActor = ActorManager.resolveActor(vNode);
	reactorID = extractID(rActor)
	Debug.console(rActor)
	Debug.console(reactorID)
	ReactionOnSelf[reactorID] = nil
	ReactionOnOther[reactorID] = nil
	Debug.console("-----SELF 2-----")
	Debug.console(ReactionOnSelf)
	Debug.console("-----OTHER 2-----")
	Debug.console(ReactionOnOther)
end

function parseName(sName)
	aParsedName = StringManager.parseWords(sName:lower())
	if StringManager.isNumberString(aParsedName[#aParsedName]) then table.remove(aParsedName) end
	if aParsedName[1] == 'hellhound' then table.insert(aParsedName, 'hound') end
	return aParsedName
end

local VISION = "VIS"
local IS_HIT = "HIT"
local IS_MISSED = "MISS"
local ATK_MELEE = "MELEE"
local ATK_RANGED = "RANGED"
local SPELL = "SPELL"
local DAMAGE = "DAMAGE"
local DIES = "DIES"
local KILLS = "KILLS"
local MAKES_SAVE = "RSAVE"
local SUCCEEDS_SAVE = "SAVES"
local FAILS_SAVE = "SAVEF"
local STARTS_TURN = "TURN"
local CRIT = "CRIT"
local HEAL = "HEAL"

function applyAttackDecorator(rSource, rTarget, rRoll)
	-- call the original applyAttack method
	ActionAttack.applyAttackReProOrig(rSource, rTarget, rRoll)

	if OptionsManager.getOption("REPRO_MSG_FORMAT") == "off" then return end
	Debug.console("---TARGET---")
	Debug.console(rTarget)
	Debug.console("---ACTION---")
	Debug.console(rRoll)
	local aFlags = {}
	if rRoll.sResult == "hit" or rRoll.sResult == "crit" then table.insert(aFlags,IS_HIT) else table.insert(aFlags,IS_MISSED) end
	if rRoll.sRange == "M" then table.insert(aFlags,ATK_MELEE) elseif rRoll.sRange == "R" then table.insert(aFlags,ATK_RANGED) end
	Debug.console(aFlags)
	reactorID = extractID(rTarget)
	if ReactionOnSelf[reactorID] ~= nil then
		for _, r in ipairs(ReactionOnSelf[reactorID]) do
			if matchReaction(aFlags, r) then
				sendChatMessage(rTarget, r)
			end
		end
	end
	for id, r in ipairs(ReactionOnOther) do
		if matchReaction(aFlags, r) then
			local sReactorCTNode = string.format("combattracker.list.id-%s", id)
			local rActor = ActorManager.resolveActor(sReactorCTNode)
			sendChatMessage(rActor, r)
		end
	end
end

function applyDamageDecorator(rSource, rTarget, rRoll)
	-- call the original applyAttack method
	ActionDamage.applyDamageReProOrig(rSource, rTarget, rRoll)

	local rDamageOutput = ActionDamage.decodeDamageText(rRoll.nTotal, rRoll.sDesc);
	if rTarget.sType ~= "npc" or rDamageOutput.sType ~= "damage" then
		-- Assume that sType == "charsheet" means it's a "PC".
		-- Heals, temporary HP, recovery etc. skipped.
		return
	end
end

function sendChatMessage(rTarget, aReaction)
	local sOutput = OptionsManager.getOption("REPRO_MSG_FORMAT")
	if sOutput == "off" then return end
	local sName = StringManager.trim(DB.getValue(aReaction.vDBRecord, "name", ""));
	local msg = ChatManager.createBaseMessage(rTarget);
	msg.icon = "react_prompt"
	msg.text = string.format("%s may be triggered", sName)
	if sOutput == "power_desc" then
		local sDesc = StringManager.trim(DB.getValue(aReaction.vDBRecord, "desc", ""));
		msg.text = msg.text .. "\n" .. sDesc
	elseif sOutput == "power_ref" then
		msg.shortcuts = {{description=sName, class="ct_power_detail", recordname=DB.getPath(aReaction.vDBRecord)}}
	elseif sOutput == "npc_ref" then
		msg.shortcuts = {{description=sName, class="npc", recordname=DB.getPath(rTarget.sCreatureNode)}}
	end
	Comm.deliverChatMessage(msg);
end

function sendParsingMessage(sName, aReaction, isOther)
	if OptionsManager.getOption("REPRO_REPORT_PARSING") == "off" then return end
	local msg = ChatManager.createBaseMessage();
	msg.text = string.format("[%s] Triggers:", sName)
	if isOther then msg.text = msg.text .. " another creature" end
	sAttackRange = "an"
	local tr = aReaction.aTrigger
	if tr[ATK_MELEE] and tr[ATK_RANGED] then sAttackRange = "a melee or ranged"
	elseif tr[ATK_MELEE] then sAttackRange = "a melee"
	elseif tr[ATK_RANGED] then sAttackRange = "a ranged" end
	if tr[IS_HIT] and tr[IS_MISSED] then msg.text = string.format("%s is hit or missed by %s attack;", msg.text, sAttackRange)
	elseif tr[IS_HIT] then msg.text = string.format("%s is hit by %s attack;", msg.text, sAttackRange)
	elseif tr[IS_MISSED] then msg.text = string.format("%s missed by %s attack;", msg.text, sAttackRange) end
	if tr[DAMAGE] then
		local sTypes = "any"
		if aReaction.aDamageType and next(aReaction.aDamageType) ~= nil then
			sTypes = table.concat(aReaction.aDamageType, "|")
		end
		msg.text = msg.text .. " takes [" .. sTypes .. "] damage;"
	end
	if tr[KILLS] then msg.text = msg.text .. " kills target;" end
	if tr[DIES] then msg.text = msg.text .. " dies;" end
	if tr[FAILS_SAVE] then msg.text = msg.text .. " fails a save;" end
	if tr[HEAL] then msg.text = msg.text .. " regains hp;" end
	Comm.deliverChatMessage(msg);
end

local aOtherOrAlly = {"another","other","ally","allies"}

function parseReaction(sName, aActorName, aPowerWords)
	Debug.console("Reaction " .. sName);
	Debug.console(aActorName);
	local aReaction = {}
	local aTrigger = {}
	aBag = makeAppearanceMap(aPowerWords, 30)
	Debug.console(aBag)
	-- When the angel is hit with an attack, they release a cloud of spores.
	-- Each creature within 10 feet of the angel must succeed on a DC 14 Constitution saving throw or be blinded
    -- until the end of the rot angel's next turn.
	local aAttacksItOrName = {"attack","attacks","it","him","her","them", unpack(aActorName)}
	-- Pattern: "When a creature [enemy|attacker] hits it [the monster] with an attack."
	if hasOneOf(aBag, {"attacker","creature","enemy"}) and 
		((hasWords(aBag, {"attack"}) and hasOneOf(aBag, {"with","against"})) or hasWords(aBag, {"attacks"})) and
		hasOneOf(aBag, {"it","him","her","them", unpack(aActorName)}) and
		appearsBefore(aBag, {"creature"}, aAttacksItOrName) and appearsBefore(aBag, {"enemy"}, aAttacksItOrName) and
		appearsBefore(aBag, aAttacksItOrName, aOtherOrAlly) -- and appearsBefore(aBag, {"attacker"}, aAttacksItOrName)
	then
		Debug.console("---- ACTIVE FORM ----")
		parseActiveForm(aBag, aTrigger)
	elseif hasWords(aBag, {"creature","starts","its","turn"}) then
		aTrigger[STARTS_TURN] = true
	elseif hasWords(aBag, {"creature","regains","hit","points"}) then
		aTrigger[HEAL] = true
	-- Pattern: "When a creature [the monster] is hit by an attack."
	elseif hasOneOf(aBag, {"when","if"}) and hasOneOf(aBag, aActorName) and
		appearsBefore(aBag, {"is", "hit", "missed", "targeted", "fails", "reduced", "reduces", "takes","attack"}, aOtherOrAlly)
	then
		Debug.console("---- PASSIVE FORM ----")
		parsePassiveForm(aBag, aTrigger)
	elseif hasWords(aBag, {"would","hit"}) then
		aTrigger[IS_HIT] = true
		parseAttackType(aBag, aTrigger)
	-- Pattern: "When another creature [that the monster can see] is hit [would be hit] by an attack."
	elseif hasOneOf(aBag, aOtherOrAlly) and hasNone(aBag, {"enemy"}) and
		appearsBefore(aBag, aOtherOrAlly, {unpack(aActorName), "is", "hit", "missed", "targeted", "fails", "reduced", "reduces", "takes","attack"})
	then
		Debug.console("---- THIRD PARTY ----")
		aReaction.sTarget = "other"
		parsePassiveForm(aBag, aTrigger)
	-- Pattern: "Enemy targets [hits] another creature with an attack."
	elseif hasWords(aBag, {"enemy"}) and hasOneOf(aBag, aOtherOrAlly) and
		appearsBefore(aBag, aOtherOrAlly, {"attack"})
	then
		Debug.console("---- THIRD PARTY ACTIVE ----")
		aReaction.sTarget = "other"
		parseActiveForm(aBag, aTrigger)
	end
	if next(aTrigger) ~= nil then
		if aReaction.sTarget ~= "other" then aReaction.sTarget = "self" end
		parseVision(aBag, aTrigger)
		aReaction.aTrigger = aTrigger
		if aTrigger[DAMAGE] and hasNone(aBag, {"damaged"}) then aReaction.aDamageType = parseDamageType(aPowerWords) end
	end
	return aReaction
end

function parseActiveForm(aBag, aTrigger)
	if hasOneOf(aBag, {"targets","makes","attacks"}) then
		aTrigger[IS_MISSED] = true
		aTrigger[IS_HIT] = true
	elseif hasWords(aBag, {"hits"}) or hasWords(aBag, {"would","hit"}) then aTrigger[IS_HIT] = true
	-- the order of this clauses is important because: "if an attack would hit .. AC++ .. if the attack then misses .."
	elseif hasWords(aBag, {"misses"}) then aTrigger[IS_MISSED] = true end
	parseAttackType(aBag, aTrigger)
end

function parsePassiveForm(aBag, aTrigger)
	if hasWords(aBag, {"is","hit"}) and hasNone(aBag, {"points","point"}) then
		aTrigger[IS_HIT] = true
		parseAttackType(aBag, aTrigger)
	elseif hasWords(aBag, {"is","missed"}) then
		aTrigger[IS_MISSED] = true
		parseAttackType(aBag, aTrigger)
	elseif hasWords(aBag, {"is","targeted"}) then
		aTrigger[IS_MISSED] = true
		aTrigger[IS_HIT] = true
		parseAttackType(aBag, aTrigger)
	elseif hasWords(aBag, {"fails","saving","throw"}) then aTrigger[FAILS_SAVE] = true
	elseif hasWords(aBag, {"damaged","by"}) then
		aTrigger[DAMAGE] = true
		parseAttackType(aBag, aTrigger)
	elseif hasWords(aBag, {"reduces"}) then aTrigger[KILLS] = true
	elseif (hasWords(aBag, {"is","reduced"}) and hasOneOf(aBag, {"0","zero"})) or hasWords(aBag, {"dies"}) then aTrigger[DIES] = true
	-- the order of these elseif clauses is important because of "when X dies, each creature around takes N damage"
	elseif hasWords(aBag, {"takes","damage"}) or hasWords(aBag, {"is","subjected","damage"}) then
		aTrigger[DAMAGE] = true
	end
end

function parseAttackType(aBag, aTrigger)
	if hasNone(aBag, {"attack"}) then return end
	if hasNone(aBag, {"melee","ranged","spell"}) then
		aTrigger[ATK_MELEE] = true
		aTrigger[ATK_RANGED] = true
		aTrigger[SPELL] = true
	else
		if hasWords(aBag, {"melee"}) then aTrigger[ATK_MELEE] = true end
		if hasWords(aBag, {"ranged"}) then aTrigger[ATK_RANGED] = true end
		if hasWords(aBag, {"spell"}) then aTrigger[SPELL] = true end
	end
end

function parseVision(aBag, aTrigger)
	if hasWords(aBag, {"can","see"}) or hasWords(aBag, {"able","to","see"}) then aTrigger[VISION] = true end
end

function parseDamageType(aPowerWords)
	aDamageTypes = {}
	i = 1
	while i <= #aPowerWords and not StringManager.isWord(aPowerWords[i], "damage") do i = i + 1	end
	if i >= #aPowerWords then return aDamageTypes end
	while i > 1 and not StringManager.isWord(aPowerWords[i], {"takes", "subjected"}) do if StringManager.isWord(aPowerWords[i], DataCommon.dmgtypes) then table.insert(aDamageTypes, aPowerWords[i]) end
		i = i - 1
	end
	return aDamageTypes
end

function parseTrait(sName, aActorName, aPowerWords)
	Debug.console("Trait " .. sName);
	if isStandard(sName, aPowerWords) then
		return {}
	end
	local aTrigger = {}
	aBag = makeAppearanceMap(aPowerWords, 32)
	Debug.console(aBag)
	if hasWords(aBag, {"creature","touches","or","hits"}) and hasOneOf(aBag, aActorName) then
		aTrigger[IS_HIT] = true
		parseAttackType(aBag, aTrigger)
	elseif hasOneOf(aBag, {"when","if"}) and hasOneOf(aBag, aActorName) and
		appearsBefore(aBag, aActorName, {"allies","ally","one","other","another"})
	then
		parsePassiveForm(aBag, aTrigger)
	end
	local aReaction = {}
	if next(aTrigger) ~= nil then
		aReaction.sTarget = "self"
		aReaction.aTrigger = aTrigger
		if aTrigger[DAMAGE] and hasNone(aBag, {"damaged"}) then aReaction.aDamageType = parseDamageType(aPowerWords) end
	end
	return aReaction
end

local standardTraits = {avoidance=true,evasion=true,["magic resistance"]=true,["gnome cunning"]=true,["magic weapons"]=true,
	["hellish weapons"]=true,["angelic weapons"]=true,["improved critical"]=true,["superior critical"]=true,regeneration=true,
	["innate spellcasting"]=true,spellcasting=true,minion=true}

function isStandard(sName, aPowerWords)
	if standardTraits[sName] then return true end
	if string.find(sName, "charge") or string.find(sName, "pounce") then
		return true
	end
end

function makeAppearanceMap(aPowerWords, nLimit)
	result = {}
	for i, w in ipairs(aPowerWords) do
		if i > nLimit then return result end
		--uncomment to remove "'s" like in "balor's"
		--if #w > 2 and w:sub(#w-1, #w-1) == "'" then w = w:sub(0, -2) end
		if result[w] == nil then result[w] = i end
	end
	return result
end

function hasWords(aBag, aWords)
	for _, w in ipairs(aWords) do
		if aBag[w] == nil then return false end
	end
	return true
end

function hasOneOf(aBag, aWords)
	for _, w in ipairs(aWords) do
		if aBag[w] ~= nil then return true end
	end
	return false
end

function hasNone(aBag, aWords)
	for _, w in ipairs(aWords) do
		if aBag[w] ~= nil then return false end
	end
	return true
end

-- Check that every word in aLeft appears earlier than every word in aRight
-- Returns true if none of the words from one of the arguments are present
function appearsBefore(aBag, aLeft, aRight)
	maxLeft = 0
	for i = 0, #aLeft, 1 do
		if aBag[aLeft[i]] ~= nil then maxLeft = math.max(maxLeft, aBag[aLeft[i]]) end
	end
	minRight = 999
	for i = 0, #aRight, 1 do
		if aBag[aRight[i]] ~= nil then minRight = math.min(minRight, aBag[aRight[i]]) end
	end
	Debug.console(string.format("left: %d; right %d;", maxLeft, minRight))
	return maxLeft < minRight
end

-- function findSequence(aPowerWords, aSequence)
-- 	local i = 1
-- 	local j = 1
-- 	while i <= #aPowerWords do
-- 		while aPowerWords[i] ~= aSequence[j] and i <= #aPowerWords do
-- 			i = i + 1
-- 		end
-- 		j = j + 1
-- 		if j > #aSequence then
-- 			return i
-- 		end
-- 	end
-- 	return nil
-- end
