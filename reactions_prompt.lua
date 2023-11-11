function registerOptions()
	OptionsManager.registerOption2("REPRO_MSG_FORMAT", false, "option_header_REPRO", "option_label_REPRO_chat_output", "option_entry_cycler",
		{ labels = "option_val_npc_link|option_val_power_desc|option_val_off", values = "npc_ref|power_desc|off", baselabel = "option_val_power_link", baseval = "power_ref", default = "option_val_power_link" });
	OptionsManager.registerOption2("REPRO_REPORT_PARSING", false, "option_header_REPRO", "option_label_REPRO_report_parsing", "option_entry_cycler",
		{ labels = "option_val_on", values = "on", baselabel = "option_val_off", baseval = "off", default = "off" });
	OptionsManager.registerOption2("REPRO_RECIPIENT", false, "option_header_REPRO", "option_label_REPRO_message_recipients", "option_entry_cycler",
		{ labels = "option_val_everyone", values = "everyone", baselabel = "option_val_only_gm", baseval = "gm", default = "gm" });
end

function onInit()
	registerOptions()

	onNPCPostAddReProOrig = CombatRecordManager.getRecordTypePostAddCallback("npc")
	CombatRecordManager.setRecordTypePostAddCallback("npc", postNPCAddDecorator);

	ActionAttack.applyAttackReProOrig = ActionAttack.applyAttack
	ActionAttack.applyAttack = applyAttackDecorator

	ActionDamage.applyDamageReProOrig = ActionDamage.applyDamage
	ActionDamage.applyDamage = applyDamageDecorator;
end

local isCTScanDone = false
local ReactionOnSelf = {}
local ReactionOnOther = {}

function addReaction(aTable, sID, aReaction)
	if aTable[sID] == nil then aTable[sID] = {aReaction}
	else table.insert(aTable[sID], aReaction) end
end

function ctListScan(ctNode)
	if isCTScanDone then return false end
	if type(ctNode) ~= "databasenode" then _, ctNode = ActorManager.getTypeAndNode(ctNode); end
	for _,v in pairs(DB.getChildren(DB.getParent(ctNode))) do
		scanActor(v)
	end
	isCTScanDone = true
	return true
end

function postNPCAddDecorator(tCustom)
	-- Call the original onNPCPostAdd callback
	onNPCPostAddReProOrig(tCustom)
	if not tCustom.nodeRecord or not tCustom.nodeCT then
		return;
	end
	if not ctListScan(tCustom.nodeCT) then scanActor(tCustom.nodeCT) end
end

function scanActor(ctNode)
	local rActor = ActorManager.resolveActor(ctNode);
	if rActor.sType ~= "npc" then return end
	aParsedName = parseName(rActor.sName)
	reactorID = extractID(rActor)
	for _,v in ipairs(DB.getChildList(ctNode, "reactions")) do
		local sName = StringManager.trim(DB.getValue(v, "name", ""));
		local sDesc = StringManager.trim(DB.getValue(v, "desc", ""));
		r = parseReaction(sName:lower(), aParsedName, StringManager.parseWords(sDesc:lower()))
		-- Debug.console(r)
		if r.aTrigger ~= nil and next(r.aTrigger) ~= nil then
			r.vDBRecord = v
			if r.isSelf then
				addReaction(ReactionOnSelf, reactorID, r)
				sendParsingMessage(sName, r, false)
			end
			if r.isOther then
				addReaction(ReactionOnOther, reactorID, r)
				sendParsingMessage(sName, r, true)
			end
		end
	end
	for _,v in ipairs(DB.getChildList(ctNode, "traits")) do
		local sName = StringManager.trim(DB.getValue(v, "name", ""));
		local sDesc = StringManager.trim(DB.getValue(v, "desc", ""));
		tr = parseTrait(sName:lower(), aParsedName, StringManager.parseWords(sDesc:lower()))
		if tr.aTrigger ~= nil and next(tr.aTrigger) ~= nil then
			tr.vDBRecord = v
			addReaction(ReactionOnSelf, reactorID, tr)
			sendParsingMessage(sName, tr, false)
		end
		-- Debug.console(tr)
	end
	DB.addHandler(ctNode, "onDelete", onCombatantDelete);
end

function extractID(rActor)
	local _,_,reactorID = string.find(rActor.sCTNode, "-(%d+)$")
	return reactorID
end

function onCombatantDelete(vNode)
	DB.removeHandler(vNode, "onDelete", onCombatantDelete);
	local rActor = ActorManager.resolveActor(vNode);
	reactorID = extractID(rActor)
	ReactionOnSelf[reactorID] = nil
	ReactionOnOther[reactorID] = nil
end

function parseName(sName)
	aParsedName = StringManager.parseWords(sName:lower())
	if StringManager.isNumberString(aParsedName[#aParsedName]) then table.remove(aParsedName) end
	if aParsedName[1] == 'hellhound' then table.insert(aParsedName, 'hound')
	elseif aParsedName[1] == 'ancient' or aParsedName[1] == 'adult' then
		for i = 1, #aParsedName, 1 do
			if aParsedName[i] == 'greatwyrm' then table.insert(aParsedName, 'dragon') end
			if aParsedName[i] == 'wyrm' then table.insert(aParsedName, 'dragon') end
		end
	end
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

function matchReaction(aAction, aReaction, rTarget)
	-- TODO: maybe match: atk: range + result + damage ? Implication is what if the type is not known.
	Debug.console("REACTION: ", aReaction)
	if next(aAction.aFlags) == nil then return false end
	for f, _ in pairs(aAction.aFlags) do
		if aReaction.aTrigger[f] == nil then return false end
	end
	if aAction.aFlags[DAMAGE] then
		if next(aReaction.aDamageTypes) ~= nil then
			foundDamageType = false
			for _, t in ipairs(aAction.aDamageTypes) do
				for _, rt in ipairs(aReaction.aDamageTypes) do if t == rt then foundDamageType = true end end
			end
			Debug.console("DMG TYPES ", aReaction.aDamageType, aAction.aDamageTypes, foundDamageType)
			if not foundDamageType then return false end
		end
	end
	local _, nodeTarget = ActorManager.getTypeAndNode(rTarget);
	if DB.getValue(nodeTarget, "reaction", 0) ~= 0 then
		return false
	end
	-- TODO: add passive reactions that work independently of condition.
	if not aAction.aFlags[DIES] and (EffectManager5E.hasEffectCondition(rTarget, "Unconscious") or
		EffectManager5E.hasEffectCondition(rTarget, "Stunned") or
		EffectManager5E.hasEffectCondition(rTarget, "Paralyzed") or
		EffectManager5E.hasEffectCondition(rTarget, "Incapacitated") or
		EffectManager5E.hasEffectCondition(rTarget, "Petrified"))
	then
		return false
	end
	if aReaction.aTrigger[VISION] and EffectManager5E.hasEffectCondition(rTarget, "Blinded") then
		return false
	end
	return true
end

function matchAllReactions(aAction, rTarget)
	Debug.console(" FLAGS: ", aAction)
	reactorID = extractID(rTarget)
	if ReactionOnSelf[reactorID] ~= nil then
		for _, rs in ipairs(ReactionOnSelf[reactorID]) do
			if matchReaction(aAction, rs, rTarget) then sendChatMessage(rTarget, rs) end
		end
	end
	-- TODO: reaction on others not necessarily work on self. Currently triggered.
	for id, reactionsList in pairs(ReactionOnOther) do
		local sReactorCTNode = string.format("combattracker.list.id-%s", id)
		local rActor = ActorManager.resolveActor(sReactorCTNode)
		for _, ro in ipairs(reactionsList) do
			if matchReaction(aAction, ro, rActor) then sendChatMessage(rActor, ro, rActor) end
		end
	end
end

function applyAttackDecorator(rSource, rTarget, rRoll)
	-- call the original applyAttack method
	ActionAttack.applyAttackReProOrig(rSource, rTarget, rRoll)

	if OptionsManager.getOption("REPRO_MSG_FORMAT") == "off" then return end
	ctListScan(rTarget)
	local aAction = {aFlags={}}
	if rRoll.sResult == "hit" or rRoll.sResult == "crit" then aAction.aFlags[IS_HIT] = true
	else aAction.aFlags[IS_MISSED] = true end
	if rRoll.sRange == "M" then aAction.aFlags[ATK_MELEE] = true
	elseif rRoll.sRange == "R" then aAction.aFlags[ATK_RANGED] = true end
	matchAllReactions(aAction, rTarget)
end

function applyDamageDecorator(rSource, rTarget, rRoll)
	-- call the original applyAttack method
	ActionDamage.applyDamageReProOrig(rSource, rTarget, rRoll)

	if OptionsManager.getOption("REPRO_MSG_FORMAT") == "off" then return end
	ctListScan(rTarget)
	local rDamageOutput = ActionDamage.decodeDamageText(rRoll.nTotal, rRoll.sDesc);
	if rTarget.sType ~= "npc" or (rDamageOutput.sType ~= "damage" and rDamageOutput.sType ~= "heal") then
		-- Assume that sType == "charsheet" means it's a "PC". Temporary HP, recovery etc. skipped.
		return
	end
	Debug.console("applyDamage", rTarget, rRoll, rDamageOutput)
	-- if rDamageOutput.nTotal == 0 then return end -- some reactions work when "subjected to damage"
	local f = {}
	if rDamageOutput.sType == "damage" then
		dmgTypes = {}
		f[DAMAGE] = true
		for k, v in pairs(rDamageOutput.aDamageTypes) do
			if v ~= 0 then table.insert(dmgTypes, k) end
		end
	elseif rDamageOutput.sType == "heal" then f[HEAL] = true end
	matchAllReactions({aFlags=f, aDamageTypes=dmgTypes}, rTarget)
	local targetStatus = ActorHealthManager.getHealthStatus(rTarget);
	if ActorHealthManager.isDyingOrDeadStatus(targetStatus) then
		matchAllReactions({aFlags={[DIES]=true}}, rTarget)
		matchAllReactions({aFlags={[KILLS]=true}}, rSource)
	end
	-- rDamageOutput.sRange == '' -- for spell;  aDamageFilter={"melee"|"ranged"}
	-- rRoll.sResults "[RESISTED]" "[EVADED]"
	-- rRoll.sDesc
end

function sendChatMessage(rTarget, aReaction)
	local sOutput = OptionsManager.getOption("REPRO_MSG_FORMAT")
	if sOutput == "off" then return end
	local sName = StringManager.trim(DB.getValue(aReaction.vDBRecord, "name", ""));
	local msg = ChatManager.createBaseMessage(rTarget);
	if OptionsManager.getOption("REPRO_RECIPIENT") == "gm" then msg.secret = true end
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
	msg.secret = true
	msg.icon = "react_prompt"
	msg.text = string.format("[%s] trigger:", sName)
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
		if aReaction.aDamageTypes and next(aReaction.aDamageTypes) ~= nil then
			sTypes = table.concat(aReaction.aDamageTypes, "|")
		end
		msg.text = msg.text .. " takes [" .. sTypes .. "] damage;"
	end
	if tr[KILLS] then msg.text = msg.text .. " kills target;" end
	if tr[DIES] then msg.text = msg.text .. " dies;" end
	if tr[FAILS_SAVE] then msg.text = msg.text .. " fails a save;" end
	if tr[HEAL] then msg.text = msg.text .. " regains hp;" end
	if tr[STARTS_TURN] then msg.text = msg.text .. " a creature starts its turn;" end
	Comm.deliverChatMessage(msg);
end

function parseReaction(sName, aActorName, aPowerWords)
	Debug.console("Reaction ", sName, aActorName);
	local aReaction = {isSelf=true}
	local aTrigger = {}
	aBag = makeAppearanceMap(aPowerWords, 35)
	-- Debug.console(aBag)
	local l, r, f = findEnemyAttacks(aBag, aActorName)
	if f then
		parseAttackRange(aBag, l, r, aTrigger)
		parseAttackResult(aBag, l, r, aTrigger)
	end
	if not f then l, r, f = findMonsterIsAttacked(aBag, aActorName)
		if f then
			parseAttackRange(aBag, l, r, aTrigger)
			parseAttackResult(aBag, l, r, aTrigger)
		end
	end
	if not f then l, r, f = findMonsterDamaged(aBag, aActorName)
		if f then
			aTrigger[DAMAGE] = true
		end
	end
	if not f then l, r, f = findMonsterDamagedByAttack(aBag, aActorName)
		if f then
			aTrigger[DAMAGE] = true
			aTrigger[IS_HIT] = true
			parseAttackRange(aBag, l, r, aTrigger)
		end
	end
	if not f then l, r, f = findMonsterKills(aBag, aActorName)
		if f then
			aTrigger[KILLS] = true
		end
	end
	if not f then l, r, f = findMonsterDies(aBag, aActorName)
		if f then
			aTrigger[DIES] = true
		end
	end
	if not f then l, r, f = findWouldBeHit(aBag, aActorName)
		if f then
			aTrigger[IS_HIT] = true
			parseAttackRange(aBag, l, r, aTrigger)
		end
	end
	if not f then l, r, f = findOtherIsHit(aBag, aActorName)
		if f then
			parseAttackRange(aBag, l, r, aTrigger)
			parseAttackResult(aBag, l, r, aTrigger)
			aReaction.isOther = true; aReaction.isSelf = false
		end
	end
	if not f then l, r, f = findOtherDamaged(aBag, aActorName)
		if f then
			aTrigger[DAMAGE] = true
			aReaction.isOther = true; aReaction.isSelf = false
		end
	end
	if not f then l, r, f = findOtherDies(aBag, aActorName)
		if f then
			aTrigger[DIES] = true
			aReaction.isOther = true; aReaction.isSelf = false
		end
	end
	if not f then l, r, f = findOtherKills(aBag, aActorName)
		if f then
			aTrigger[KILLS] = true
			aReaction.isOther = true; aReaction.isSelf = false
		end
	end
	if not f then l, r, f = findOtherFailsSave(aBag, aActorName)
		if f then
			aTrigger[FAILS_SAVE] = true
			aReaction.isOther = true; aReaction.isSelf = false
		end
	end
	-- When another creature within 60 feet of the commander who can hear and understand them
	-- makes a saving throw, the commander can give that creature advantage on the saving throw.
	if not f then l, r, f = enemyAttacksAllies(aBag, aActorName)
		if f then
			parseAttackRange(aBag, l, r, aTrigger)
			parseAttackResult(aBag, l, r, aTrigger)
			aReaction.isOther = true; aReaction.isSelf = false
		end
	end
	if not f then l, r, f = selfOrAllyAttacked(aBag, aActorName)
		if f then
			aTrigger[IS_HIT] = true; aTrigger[ATK_MELEE] = true; aTrigger[ATK_RANGED] = true;
			aReaction.isOther = true; aReaction.isSelf = true
		end
	end
	if not f then l, r, f = sequencePos(aBag, {"creature","regains","hit","points"})
		if f then
			aTrigger[HEAL] = true
			aReaction.isOther = true; aReaction.isSelf = false
		end
	end
	if next(aTrigger) ~= nil then
		parseVision(aBag, l, r, aTrigger)
		aReaction.aTrigger = aTrigger
		if aTrigger[DAMAGE] then aReaction.aDamageTypes = parseDamageType(aPowerWords, l, r) end
	end
	return aReaction
end

local enemy = {"creature", "enemy", "attacker"}
local hitsOrMisses = {"hits", "misses", "targets"}
local otherOrAlly = {"another","other","ally","allies"}
function findEnemyAttacks(aBag, actorName)
	local monster = {"it","him","her","them", unpack(actorName)}
	local l, r, f = sequencePos(aBag, {enemy, "within", "feet", monster, hitsOrMisses, "attack"})
	if not f then 
		l, r, f = sequencePos(aBag, {enemy, hitsOrMisses, monster, "attack"})
	end
	if not f then
		l, r, f = sequencePos(aBag, {enemy, monster, "can", "see", hitsOrMisses, "attack"})
	end
	if not f then
		l, r, f = sequencePos(aBag, {enemy, "attacks", monster})
	end
	if f and hasNoneWithin(aBag, 0, r, otherOrAlly) then return l, r, f end
	return 0, 0, false
end

local isHit = {"hit", "missed", "targeted"}
function findMonsterIsAttacked(aBag, actorName)
	local monster = {"it","him","her","them", unpack(actorName)}
	l, r, f = sequencePos(aBag, {{"when", "if"}, monster, isHit, "attack"})
	if f and hasNoneWithin(aBag, 0, r, {"creature", unpack(otherOrAlly)}) then return l, r, f end
	return 0, 0, false
end

function findMonsterDamagedByAttack(aBag, actorName)
	local l, r, f = sequencePos(aBag, {"damaged", "by", "attack"})
	if f and hasNoneWithin(aBag, 0, r, otherOrAlly) then return l, r, f end
	return 0, 0, false
end

function findMonsterDamaged(aBag, actorName)
	local l, r, f = sequencePos(aBag, {actorName, "subjected", "to", "damage"})
	if not f then
		l, r, f = sequencePos(aBag, {"damaged", "by", "creature", "within", "feet", actorName})
	end
	if not f then
		l, r, f = sequencePos(aBag, {actorName, "takes", "damage"})
	end
	if not f then
		l, r, f = sequencePos(aBag, {enemy, "deals", "damage", {"it","him","her","them", unpack(actorName)}})
	end
	if not f then
		l, r, f = sequencePos(aBag, {enemy, actorName, "can", "see", "deals", "damage"})
	end
	if not f then
		l, r, f = sequencePos(aBag, {"after", "taking", "damage", "attack"})
	end
	if f and hasNoneWithin(aBag, 0, r, otherOrAlly) then return l, r, f end
	return 0, 0, false
end

function findMonsterDies(aBag, actorName)
	local l, r, f = sequencePos(aBag, {actorName, "dies"})
	if not f then
		l, r, f = sequencePos(aBag, {actorName, "reduced", {"0", "zero"}})
	end
	if f and hasNoneWithin(aBag, 0, r, {"who", unpack(otherOrAlly)}) then return l, r, f end
	return 0, 0, false
end

function findMonsterKills(aBag, actorName)
	local l, r, f = sequencePos(aBag, {actorName, "kills"})
	if not f then
		l, r, f = sequencePos(aBag, {actorName, "reduces", {"0", "zero"}})
	end
	if f and hasNoneWithin(aBag, 0, r, otherOrAlly) then return l, r, f end
	return 0, 0, false
end

function findMonsterFailsSave(aBag, actorName)
	return sequencePos(aBag, {actorName, "fails", "saving", "throw"})
end

function findWouldBeHit(aBag)
	return sequencePos(aBag, {"against", "attack", "that", "would", "hit"})
end

-- When another creature the dragon can see within 15 feet is hit by an attack, the dragon deflects the attack, turning the hit into a miss.
function findOtherIsHit(aBag, actorName)
	local l, r, f = sequencePos(aBag, {{"creature", unpack(otherOrAlly)}, isHit, {"by", "with"}, "attack"})
	if not f then
		l, r, f = sequencePos(aBag, {enemy, hitsOrMisses, otherOrAlly, "attack"})
	end
	return l, r, f
end

function findOtherDamaged(aBag, actorName)
	return sequencePos(aBag, {otherOrAlly, "takes", "damage"})
end

--When a creature who the cackler can see within 30 feet of them dies,
-- the cackler magically teleports into the space the creature occupied.
function findOtherDies(aBag, actorName)
	local l, r, f = sequencePos(aBag, {otherOrAlly, "dies"})
	if not f then
		l, r, f = sequencePos(aBag, {otherOrAlly, "reduced", {"0", "zero"}})
	end
	if not f then
		l, r, f = sequencePos(aBag, {"creature", actorName, "see", "dies"})
	end
	return l, r, f
end

function findOtherKills(aBag, actorName)
	local l, r, f = sequencePos(aBag, {otherOrAlly, "kills"})
	if not f then
		l, r, f = sequencePos(aBag, {otherOrAlly, "reduces", {"0", "zero"}})
	end
	return l, r, f
end

function findOtherFailsSave(aBag, actorName)
	return sequencePos(aBag, {otherOrAlly, "fails", "saving", "throw"})
end

function enemyAttacksAllies(aBag, actorName)
	return sequencePos(aBag, {enemy, actorName, "see", "attacks", otherOrAlly})
end

function selfOrAllyAttacked(aBag, actorName)
	local l, r, f = sequencePos(aBag, {actorName, "creature", "attacked"})
	if not f then
		l, r, f = sequencePos(aBag, {"creature", actorName, "attacked"})
	end
	return l, r, f
end

function parseAttackRange(aBag, l, r, aTrigger)
	if hasNoneWithin(aBag, l, r, {"melee","ranged","spell"}) then
		aTrigger[ATK_MELEE] = true
		aTrigger[ATK_RANGED] = true
		aTrigger[SPELL] = true
	else
		if hasWordsWithin(aBag, l, r, {"melee"}) then aTrigger[ATK_MELEE] = true end
		if hasWordsWithin(aBag, l, r, {"ranged"}) then aTrigger[ATK_RANGED] = true end
		if hasWordsWithin(aBag, l, r, {"spell"}) then aTrigger[SPELL] = true end
	end
end

function parseAttackResult(aBag, l, r, aTrigger)
	if hasNoneWithin(aBag, l, r, {"hits","hit","misses","miss"}) then
		aTrigger[IS_MISSED] = true
		aTrigger[IS_HIT] = true
	else
		if hasOneOfWithin(aBag, l, r, {"hits","hit"}) then aTrigger[IS_HIT] = true end
		if hasOneOfWithin(aBag, l, r, {"misses","miss"}) then aTrigger[IS_MISSED] = true end
	end
end

function parseVision(aBag, l, r, aTrigger)
	if hasWordsWithin(aBag, l, r, {"can","see"}) or hasWordsWithin(aBag, l, r, {"able","to","see"}) then aTrigger[VISION] = true end
end

function parseDamageType(aPowerWords, l, r)
	aDamageTypes = {}
	i = r
	while i > l and not StringManager.isWord(aPowerWords[i], {"takes", "subjected"}) do if StringManager.isWord(aPowerWords[i], DataCommon.dmgtypes) then table.insert(aDamageTypes, aPowerWords[i]) end
		i = i - 1
	end
	return aDamageTypes
end

function parseTrait(sName, aActorName, aPowerWords)
	Debug.console("Trait " .. sName);
	if isStandard(sName, aPowerWords) then
		return {}
	end
	local aReaction = {isSelf=true}
	local aTrigger = {}
	aBag = makeAppearanceMap(aPowerWords, 35)
	-- Debug.console(aBag)
	local l, r, f = findMonsterKills(aBag, aActorName)
	if f then aTrigger[KILLS] = true end
	if not f then l, r, f = findMonsterDies(aBag, aActorName)
		if f then aTrigger[DIES] = true end
	end
	if not f then l, r, f = sequencePos(aBag, {"creature","touches","hits", "attack"})
		if f then
			aTrigger[IS_HIT] = true
			parseAttackRange(aBag, l, r, aTrigger)
		end
	end
	if not f then l, r, f = findMonsterFailsSave(aBag, aActorName)
		if f then aTrigger[FAILS_SAVE] = true end
	end
	if not f then l, r, f = sequencePos(aBag, {"creature","starts","its","turn"})
		if f then
			aTrigger[STARTS_TURN] = true
			aReaction.isOther = true; aReaction.isSelf = false
		end
	end
	-- Order is important since: "a creature that touches ... takes damage" or "when fails a save .. takes damage"
	if not f then l, r, f = findMonsterDamaged(aBag, aActorName)
		if f then aTrigger[DAMAGE] = true end
	end
	if next(aTrigger) ~= nil then
		aReaction.aTrigger = aTrigger
		if aTrigger[DAMAGE] then aReaction.aDamageTypes = parseDamageType(aPowerWords, l, r) end
	end
	return aReaction
end

local standardTraits = {avoidance=true,evasion=true,["magic resistance"]=true,["gnome cunning"]=true,["magic weapons"]=true,
	["hellish weapons"]=true,["angelic weapons"]=true,["improved critical"]=true,["superior critical"]=true,regeneration=true,
	["innate spellcasting"]=true,spellcasting=true,minion=true,incorporeal=true}

function isStandard(sName, aPowerWords)
	if standardTraits[sName] then return true end
	if string.find(sName, "charge") or string.find(sName, "pounce") then
		return true
	end
end

function makeAppearanceMap(aPowerWords, nLim)
	result = {}
	for i, w in ipairs(aPowerWords) do
		--uncomment to remove "'s" like in "balor's"
		--if #w > 2 and w:sub(#w-1, #w-1) == "'" then w = w:sub(0, -2) end
		if result[w] == nil then result[w] = i end
		if nLim ~= nil and i > nLim then return result end
	end
	return result
end

function hasWordsWithin(aBag, l, r, aWords)
	for _, w in ipairs(aWords) do
		if aBag[w] == nil or aBag[w] < l or aBag[w] > r then return false end
	end
	return true
end

function hasOneOfWithin(aBag, l, r, aWords)
	for _, w in ipairs(aWords) do
		if aBag[w] ~= nil and aBag[w] > l and aBag[w] < r then return true end
	end
	return false
end

function hasNoneWithin(aBag, l, r, aWords)
	-- Debug.console(aWords)
	-- Debug.console("%d %d", l, r)
	for _, w in ipairs(aWords) do
		if aBag[w] ~= nil and aBag[w] > l and aBag[w] < r then return false end
	end
	return true
end

-- Check that every word in aLeft appears earlier than every word in aRight.
-- Returns true if none of the words from one of the arguments are present.
function appearsBefore(aBag, aLeft, aRight)
	maxLeft = 0
	for i = 0, #aLeft, 1 do
		if aBag[aLeft[i]] ~= nil then maxLeft = math.max(maxLeft, aBag[aLeft[i]]) end
	end
	minRight = 999
	for i = 0, #aRight, 1 do
		if aBag[aRight[i]] ~= nil then minRight = math.min(minRight, aBag[aRight[i]]) end
	end
	return maxLeft < minRight
end

-- If the sequence not found, returns zero, otherwise returns index of the last element.
-- Next word in the sequence must appear after the previous one.
-- aSeq is in form: {"str", {"opt_1", "opt_2", "opt_n"}, "other_str"}.
-- Any optional strings found in aBag will satisfy the check.
function sequencePos(aBag, aSeq)
	local nFirst = 0
	local nLast = 0
	-- Debug.console("--------------------")
	-- Debug.console(aSeq)
	for i = 1, #aSeq, 1 do
		if type(aSeq[i]) == "table" then
			local subseq = aSeq[i]
			local subseqPos = 999
			for j = 1, #subseq, 1 do
				local nPos = aBag[subseq[j]]
				if nPos ~= nil and nPos < subseqPos then subseqPos = nPos end
			end
			if subseqPos == nil or subseqPos == 999 or subseqPos < nLast then return 0, 0, false end
			nLast = subseqPos
		else
			local nPos = aBag[aSeq[i]]
			if nPos == nil or nPos < nLast then return 0, 0, false end
			nLast = nPos
		end
		if i == 1 then nFirst = nLast end
	end
	return nFirst, nLast, true
end
