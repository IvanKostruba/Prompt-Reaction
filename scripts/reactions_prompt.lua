local CombatGroupsLoaded = false

function registerOptions()
	OptionsManager.registerOption2("REPRO_MSG_FORMAT", false, "option_header_REPRO", "option_label_REPRO_chat_output", "option_entry_cycler",
		{ labels = "option_val_npc_link|option_val_power_desc|option_val_off", values = "npc_ref|power_desc|off", baselabel = "option_val_power_link", baseval = "power_ref", default = "option_val_power_link" })
	OptionsManager.registerOption2("REPRO_REPORT_PARSING", false, "option_header_REPRO", "option_label_REPRO_report_parsing", "option_entry_cycler",
		{ labels = "option_val_on|option_val_ct_add_only", values = "on|npc_add", baselabel = "option_val_off", baseval = "off", default = "off" })
	OptionsManager.registerOption2("REPRO_RECIPIENT", false, "option_header_REPRO", "option_label_REPRO_message_recipients", "option_entry_cycler",
		{ labels = "option_val_everyone", values = "everyone", baselabel = "option_val_only_gm", baseval = "gm", default = "gm" })
	OptionsManager.registerOption2("REPRO_EFFECT_WARN", false, "option_header_REPRO", "option_label_REPRO_effect_warning", "option_entry_cycler",
		{ labels = "option_val_on", values = "on", baselabel = "option_val_off", baseval = "off", default = "off" })
	OptionsManager.registerOption2("REPRO_WARN_HIDDEN_TOKENS", false, "option_header_REPRO", "option_label_REPRO_hidden_tokens", "option_entry_cycler", 
		{ labels = "option_val_off", values = "off", baselabel = "option_val_on", baseval = "on", default = "on" })
	--Register option for if Combat Groups extension is loaded
	if CombatGroupsLoaded then
		OptionsManager.registerOption2("REPRO_WARN_HIDDEN_GROUPS", false, "option_header_REPRO", "option_label_REPRO_hidden_groups", "option_entry_cycler", 
		{ labels = "option_val_on", values = "on", baselabel = "option_val_off", baseval = "off", default = "off" })
	end
end

function onInit()
	for _, name in pairs(Extension.getExtensions()) do
		if name == "CombatGroups" then CombatGroupsLoaded = true end
	end

	registerOptions()

	onNPCPostAddReProOrig = CombatRecordManager.getRecordTypePostAddCallback("npc")
	CombatRecordManager.setRecordTypePostAddCallback("npc", postNPCAddDecorator)

	ActionHeal.onHealReProOrig = ActionHeal.onHeal
	ActionHeal.onHeal = onHealDecorator
	ActionsManager.registerResultHandler("heal", ActionHeal.onHeal)

	ActionAttack.applyAttackReProOrig = ActionAttack.applyAttack
	ActionAttack.applyAttack = applyAttackDecorator

	ActionDamage.applyDamageReProOrig = ActionDamage.applyDamage
	ActionDamage.applyDamage = applyDamageDecorator

	ActionSave.applySaveReProOrig = ActionSave.applySave
	ActionSave.applySave = applySaveDecorator

	PowerManager.performActionReProOrig = PowerManager.performAction
	PowerManager.performAction = performActionDecorator

	ActionCheck.onRollReProOrig = ActionCheck.onRoll
	ActionCheck.onRoll = checkRollDecorator
	-- have to re-register since we replaced the registered function
	ActionsManager.registerResultHandler("check", ActionCheck.onRoll)

	ActionSkill.onRollReProOrig = ActionSkill.onRoll
	ActionSkill.onRoll = skillRollDecorator
	ActionsManager.registerResultHandler("skill", ActionSkill.onRoll)

	CombatManager.setCustomTurnStart(onTurnStart) -- adds a listener, no need for a decorator
end

local isCTScanDone = false
local ReactionOnSelf = {}
local ReactionOnOther = {}

function addReaction(aTable, sID, rReact)
	if aTable[sID] == nil then aTable[sID] = {rReact}
	else table.insert(aTable[sID], rReact) end
end

function ctListScan(ctNode)
	if isCTScanDone or (type(ctNode) ~= "databasenode" and ctNode.sCTNode == nil) then return false end
	if type(ctNode) ~= "databasenode" then ctNode = DB.findNode(ctNode.sCTNode) end
	for _,v in pairs(DB.getChildren(DB.getParent(ctNode))) do
		scanActor(v, true)
	end
	isCTScanDone = true
	return true
end

function postNPCAddDecorator(tCustom)
	-- Call the original onNPCPostAdd callback
	onNPCPostAddReProOrig(tCustom)
	if not tCustom.nodeRecord or not tCustom.nodeCT then
		return
	end
	if not ctListScan(tCustom.nodeCT) then scanActor(tCustom.nodeCT, false) end
end

function scanActor(ctNode, isBulk)
	local rActor = ActorManager.resolveActor(ctNode)
	if rActor.sType ~= "npc" then return end
	aParsedName = parseName(rActor.sName)
	reactorID = extractID(rActor)
	processNodeData(ctNode, "reactions", parseReaction, aParsedName, reactorID, isBulk)
	processNodeData(ctNode, "traits", parseTrait, aParsedName, reactorID, isBulk)
	processNodeData(ctNode, "spells", parseSpell, aParsedName, reactorID, isBulk)
	DB.addHandler(ctNode, "onDelete", onCombatantDelete)
end

function processNodeData(ctNode, sRecordType, fParser, aParsedName, reactorID, isBulk)
	for _,v in ipairs(DB.getChildList(ctNode, sRecordType)) do
		local sName = StringManager.trim(DB.getValue(v, "name", ""))
		local sDesc = StringManager.trim(DB.getValue(v, "desc", ""))
		r = fParser(sName:lower(), aParsedName, StringManager.parseWords(sDesc:lower()))
		if r.aTrigger ~= nil and next(r.aTrigger) ~= nil then
			r.vDBRecord = v
			insertReaction(sName, reactorID, r, isBulk)
		end
	end
end

function insertReaction(sName, id, r, isBulk)
	if r.isSelf then
		addReaction(ReactionOnSelf, id, r)
		sendParsingMessage(sName, r, false, isBulk)
	end
	if r.isOther then
		addReaction(ReactionOnOther, id, r)
		sendParsingMessage(sName, r, true, isBulk)
	end
end

function extractID(rActor)
	-- this can happen then check is rolled from a party sheet and some PCs are not in tracker.
	if rActor == nil or rActor.sCTNode == nil then return nil end
	local _,_,reactorID = string.find(rActor.sCTNode, "-(%d+)$")
	return reactorID
end

function onCombatantDelete(vNode)
	DB.removeHandler(vNode, "onDelete", onCombatantDelete)
	local rActor = ActorManager.resolveActor(vNode)
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
local CAST = "CAST"
local DAMAGE = "DAMAGE"
local DIES = "DIES"
local KILLS = "KILLS"
local ROLL_SAVE = "RSAVE"
local FAILS_SAVE = "SAVEF"
local PASS_SAVE = "SAVES"
local FAILS_ATTR = "ATTRF"
local PASS_ATTR = "ATTRS"
local STARTS_TURN = "TURN"
local CRIT = "CRIT"
local HEAL = "HEAL"
local ATK_FAIL = "ATK_FAIL"
local ATK_HITS = "ATK_HITS"
local BLOODIED = "BLOODIED"

-- rOrigTarget always come from the roll
-- rTarget is resolved from the combatant ID when evaluating reactions on others
function tryTriggerReaction(aAction, rReact, rTarget, rOrigTarget, rSource)
	if next(aAction.aFlags) == nil then return false end
	for f, _ in pairs(aAction.aFlags) do
		if rReact.aTrigger[f] == nil then return false end
	end
	if aAction.aFlags[DAMAGE] then
		if next(rReact.aDamageTypes) ~= nil then
			local foundDamageType = false
			for _, t in ipairs(aAction.aDamageTypes) do
				for _, rt in ipairs(rReact.aDamageTypes) do if t == rt then foundDamageType = true end end
			end
			if not foundDamageType then return false end
		end
	end
	local eff = {}
	local nodeTarget = ActorManager.getCTNode(rTarget)
	local tokenvis = DB.getValue(nodeTarget,"tokenvis",1)
	if tokenvis == 0 and OptionsManager.getOption("REPRO_WARN_HIDDEN_TOKENS") == "off" then return false end
	local groupvis = DB.getValue(nodeTarget,"groupvis",1)
	if groupvis == 0 and OptionsManager.getOption("REPRO_WARN_HIDDEN_GROUPS") == "off" then return false end
	if rReact.isPassive == nil and DB.getValue(nodeTarget, "reaction", 0) ~= 0 then
		eff.hasReacted = true
		sendWarningMessage(rTarget, eff)
		return false
	end
	local opt = {}
	if rReact.nDistEnemy ~= nil then
		local d = measureDistance(nodeTarget, rSource)
		if d ~= nil and d > rReact.nDistEnemy then opt.nDistWant = rReact.nDistEnemy; opt.nDistGot = d end
	elseif rReact.nDistAlly ~= nil and rTarget.sCTNode ~= rOrigTarget.sCTNode then
		local d = measureDistance(nodeTarget, rOrigTarget)
		if d ~= nil and d > rReact.nDistAlly then opt.nDistWant = rReact.nDistAlly; opt.nDistGot = d end
	end
	if rReact.nACBonus ~= nil and aAction.aFlags[IS_HIT] then
		-- nAtkExcess is nil if it was an automatic hit.
		opt.canSave = aAction.nAtkExcess ~= nil and aAction.nAtkExcess < rReact.nACBonus
	end
	eff.isUnconscious = EffectManager5E.hasEffectCondition(rTarget, "Unconscious")
	if eff.isUnconscious then
		if aAction.aFlags[DIES] ~= nil and rTarget.sCTNode == rOrigTarget.sCTNode
		then
			eff.isUnconscious = nil -- Unconscious in practice often means dead, but creature may have a reaction to it's demise.
		end
	end
	eff.isStunned = EffectManager5E.hasEffectCondition(rTarget, "Stunned")
	eff.isParalyzed = EffectManager5E.hasEffectCondition(rTarget, "Paralyzed")
	eff.isIncapacitated = EffectManager5E.hasEffectCondition(rTarget, "Incapacitated")
	eff.isPetrified = EffectManager5E.hasEffectCondition(rTarget, "Petrified")
	if rReact.isUnconditional == nil and
		(eff.isUnconscious or eff.isStunned or eff.isParalyzed or eff.isIncapacitated or eff.isPetrified)
	then
		sendWarningMessage(rTarget, eff)
		return false
	end
	eff.isInvisible = EffectManager5E.hasEffectCondition(rSource, "Invisible")
	eff.isBlinded = EffectManager5E.hasEffectCondition(rTarget, "Blinded")
	if rReact.aTrigger[VISION] and (eff.isBlinded or eff.isInvisible) then
		sendWarningMessage(rTarget, eff)
		return false
	end
	sendChatMessage(rTarget, rReact, opt)
	return true
end

function measureDistance(nodeT, rOther)
	if nodeT == nil or rOther == nil or rOther.sCTNode == nil then return nil end
	local tt = Token.getToken(DB.getValue(nodeT, "tokenrefnode", ""), DB.getValue(nodeT, "tokenrefid", ""))
	local nodeSrc = DB.findNode(rOther.sCTNode)
	local st = Token.getToken(DB.getValue(nodeSrc, "tokenrefnode", ""), DB.getValue(nodeSrc, "tokenrefid", ""))
	local ic = ImageManager.getImageControl(tt, false)
	if not ic or not st or not tt then return nil end
	local dist = ic.getDistanceBetween(tt, st)
	if not dist then return nil end
	return dist
end

function matchAllReactions(aAction, rTarget, rSource)
	if rTarget == nil then
		return
	end
	local reactorID = extractID(rTarget)
	if reactorID ~= nil then
		if ReactionOnSelf[reactorID] ~= nil then
			for _, rs in ipairs(ReactionOnSelf[reactorID]) do
				tryTriggerReaction(aAction, rs, rTarget, rTarget, rSource)
			end
		end
	end
	for id, reactionsList in pairs(ReactionOnOther) do
		local sReactorCTNode = string.format("combattracker.list.id-%s", id)
		local rActor = ActorManager.resolveActor(sReactorCTNode)
		if rActor.sCTNode ~= rTarget.sCTNode then
			for _, ro in ipairs(reactionsList) do
				tryTriggerReaction(aAction, ro, rActor, rTarget, rSource)
			end
		end
	end
end

function applyAttackDecorator(rSource, rTarget, rRoll)
	-- call the original applyAttack method
	ActionAttack.applyAttackReProOrig(rSource, rTarget, rRoll)

	if OptionsManager.getOption("REPRO_MSG_FORMAT") == "off" then return end
	ctListScan(rTarget)
	local aAction = {aFlags={}}
	if rRoll.sResult == "hit" or rRoll.sResult == "crit" then
		aAction.aFlags[IS_HIT] = true
		if rRoll.nFirstDie ~= 20 then aAction.nAtkExcess = rRoll.nTotal - rRoll.nDefenseVal end -- auto hits cannot be stopped
	else aAction.aFlags[IS_MISSED] = true end
	if rRoll.sRange == "M" then aAction.aFlags[ATK_MELEE] = true
	elseif rRoll.sRange == "R" then aAction.aFlags[ATK_RANGED] = true end
	matchAllReactions(aAction, rTarget, rSource)
	if rSource ~= nil then
		local flg = {}
		if aAction.aFlags[IS_HIT] then flg[ATK_HITS]=true
		else flg[ATK_FAIL]=true end
		-- reactions targeted at the attacker
		matchAllReactions({aFlags=flg}, rSource, rSource)
	end
	if rRoll.sResult == "crit" then matchAllReactions({aFlags={[CRIT]=true}}, rTarget, rSource) end
end

function applyDamageDecorator(rSource, rTarget, rRoll)
	local origDamage = rRoll.nTotal -- applyDamage modifies the roll and that leads to warning when decoding.

	-- call the original applyAttack method
	ActionDamage.applyDamageReProOrig(rSource, rTarget, rRoll)

	if OptionsManager.getOption("REPRO_MSG_FORMAT") == "off" then return end
	ctListScan(rTarget)
	local rDamageOutput = ActionDamage.decodeDamageText(origDamage, rRoll.sDesc)
	if rTarget.sType ~= "npc" or (rDamageOutput.sType ~= "damage" and rDamageOutput.sType ~= "heal") then
		-- Assume that sType == "charsheet" means it's a "PC". Temporary HP, recovery etc. skipped.
		return
	end
	-- if rDamageOutput.nTotal == 0 then return end -- some reactions work when "subjected to damage" even if it's 0
	-- rRoll.sResults "[RESISTED]" "[EVADED]"
	local f = {}
	if rDamageOutput.sType == "damage" then
		dmgTypes = {}
		f[DAMAGE] = true
		for k, v in pairs(rDamageOutput.aDamageTypes) do
			if v ~= 0 then table.insert(dmgTypes, k) end
		end
	elseif rDamageOutput.sType == "heal" then f[HEAL] = true end
	matchAllReactions({aFlags=f, aDamageTypes=dmgTypes}, rTarget, rSource)
	local targetStatus = ActorHealthManager.getHealthStatus(rTarget)
	if ActorHealthManager.isDyingOrDeadStatus(targetStatus) then
		matchAllReactions({aFlags={[DIES]=true}}, rTarget, rSource)
		matchAllReactions({aFlags={[KILLS]=true}}, rSource, rSource)
	else
		local nodeTarget = ActorManager.getCTNode(rTarget)
		local bloodiedVal = DB.getValue(nodeTarget,"hptotal",0)/2
		local wounds = DB.getValue(nodeTarget,"wounds",0)
		if bloodiedVal == 0 or wounds < bloodiedVal then return end
		if wounds - rRoll.nTotal < bloodiedVal then
			matchAllReactions({aFlags={[BLOODIED]=true}}, rTarget, rSource)
		end
	end
end

function applySaveDecorator(rSource, rOrigin, rAction, sUser)
	-- call the original applySave method
	ActionSave.applySaveReProOrig(rSource, rOrigin, rAction, sUser)

	if OptionsManager.getOption("REPRO_MSG_FORMAT") == "off" then return end
	ctListScan(rSource)
	-- ROLL_SAVE can be added here
	if rAction.nTarget > 0 then
		local flg={}
		if rAction.nTotal < rAction.nTarget then flg[FAILS_SAVE] = true
		else flg[PASS_SAVE] = true end
		-- rOrigin is who caused the save, we are interested only in who rolls for these reactions.
		matchAllReactions({aFlags=flg}, rSource, rSource)
	end
end

function onHealDecorator(rSource, rTarget, rRoll)
	-- call the original method
	ActionHeal.onHealReProOrig(rSource, rTarget, rRoll)

	ctListScan(rSource)
	matchAllReactions({aFlags={[HEAL]=true}}, rTarget, rSource)
end

function onTurnStart(nodeEntry)
	if OptionsManager.getOption("REPRO_MSG_FORMAT") == "off" then return end
	ctListScan(nodeEntry)
	local rActor = ActorManager.resolveActor(nodeEntry)
	if rActor.sType == "npc" then return end -- only PCs will trigger start turn reations
	matchAllReactions({aFlags={[STARTS_TURN]=true}}, rActor, rActor)
end

local magicSchools = {"abjuration", "divination", "evocation", "illusion", "enchantment", "transmutation", "necromancy", "conjuration"}

function performActionDecorator(draginfo, rActor, rAction, nodePower)
	local result = PowerManager.performActionReProOrig(draginfo, rActor, rAction, nodePower)

	if rActor.sType ~= "charsheet" then return result end
	if OptionsManager.getOption("REPRO_MSG_FORMAT") == "off" then return result end
	ctListScan(rActor)
	local n = DB.getValue(nodePower, "name", ""):lower()
	local s = DB.getValue(nodePower, "school", ""):lower()
	local spell = false
	if magicSchools[s] then spell = true end
	if not spell then
		local pg = DB.getValue(nodePower, "group", ""):lower()
		local node = DB.findNode(rActor.sCreatureNode)
		for _, v in ipairs(DB.getChildList(node, "powergroup")) do
			if pg == DB.getValue(v, "name", ""):lower() then
				spell = "memorization" == DB.getValue(v, "castertype", ""):lower() or
					pg == Interface.getString("power_label_groupspells"):lower()
			end
		end
	end
	if spell then
		-- castSpells[n] = true; we can store the name of the spell to associate attack or damage with it later
		matchAllReactions({aFlags={[CAST]=true}}, rActor, rActor)
	end
	return result
end

function checkRollDecorator(rSource, rTarget, rRoll)
	-- call the original onRoll method
	ActionCheck.onRollReProOrig(rSource, rTarget, rRoll)
	performAttributeCheck(rSource, rTarget, rRoll)
end

function skillRollDecorator(rSource, rTarget, rRoll)
	-- call the original onRoll method
	ActionSkill.onRollReProOrig(rSource, rTarget, rRoll)
	performAttributeCheck(rSource, rTarget, rRoll)
end

function performAttributeCheck(rSource, rTarget, rRoll)
	ctListScan(rSource)
	if rRoll.nTarget ~= nil and rRoll.nTarget ~= 0 then
		local rollTotal = ActionsManager.total(rRoll);
		local flg={}
		if rollTotal - rRoll.nTarget < 0 then flg[FAILS_ATTR] = true
		else flg[PASS_ATTR] = true end
		-- rSource is the actor who rolls the check
		matchAllReactions({aFlags=flg}, rSource, rSource)
	end
end

function sendChatMessage(rTarget, rReact, rSpecial)
	local sOutput = OptionsManager.getOption("REPRO_MSG_FORMAT")
	if sOutput == "off" then return end
	local sName = StringManager.trim(DB.getValue(rReact.vDBRecord, "name", ""))
	local msg = ChatManager.createBaseMessage(rTarget)
	if OptionsManager.getOption("REPRO_RECIPIENT") == "gm" then msg.secret = true end
	msg.icon = "react_prompt"
	msg.text = string.format("%s possibly triggered", sName)
	if rSpecial.nDistWant ~= nil then
		msg.icon = "react_distance"
		msg.text = string.format("%s is available, but distance is too long: limit is %d, measured %d feet", sName, rSpecial.nDistWant, rSpecial.nDistGot)
	elseif rSpecial.canSave ~= nil then
		if rSpecial.canSave then
			msg.icon = "deflect_arrow"
			msg.text = string.format("%s: AC bonus can deflect the attack", sName)
		else
			msg.icon = "penetrate"
			msg.text = string.format("%s: AC bonus is not enough to stop the attack", sName)
		end
	end
	if sOutput == "power_desc" then
		local sDesc = StringManager.trim(DB.getValue(rReact.vDBRecord, "desc", ""))
		msg.text = msg.text .. "\n" .. sDesc
	elseif sOutput == "power_ref" then
		msg.shortcuts = {{description=sName, class="ct_power_detail", recordname=DB.getPath(rReact.vDBRecord)}}
	elseif sOutput == "npc_ref" then
		msg.shortcuts = {{description=sName, class="npc", recordname=DB.getPath(rTarget.sCreatureNode)}}
	end
	Comm.deliverChatMessage(msg)
end

function sendParsingMessage(sName, rReact, isOther, isBulk)
	local opt = OptionsManager.getOption("REPRO_REPORT_PARSING")
	if opt == "off" or (isBulk and opt == "npc_add") then return end
	local msg = ChatManager.createBaseMessage()
	msg.secret = true
	msg.icon = "react_prompt"
	t = string.format("[%s] trigger:", sName)
	if isOther then t = t .. " another creature" end
	sAttackRange = "an"
	local tr = rReact.aTrigger
	if tr[ATK_MELEE] and tr[ATK_RANGED] then sAttackRange = "a melee or ranged"
	elseif tr[ATK_MELEE] then sAttackRange = "a melee"
	elseif tr[ATK_RANGED] then sAttackRange = "a ranged" end
	if tr[IS_HIT] and tr[IS_MISSED] then t = string.format("%s is hit or missed by %s attack;", t, sAttackRange)
	elseif tr[IS_HIT] then t = string.format("%s is hit by %s attack;", t, sAttackRange)
	elseif tr[IS_MISSED] then t = string.format("%s missed by %s attack;", t, sAttackRange) end
	if tr[CRIT] then t = t .. " suffers a critical hit;" end
	if tr[DAMAGE] then
		local sTypes = "any"
		if rReact.aDamageTypes and next(rReact.aDamageTypes) ~= nil then
			sTypes = table.concat(rReact.aDamageTypes, "|")
		end
		t = t .. " takes [" .. sTypes .. "] damage;"
	end
	if tr[KILLS] then t = t .. " kills target;" end
	if tr[DIES] then t = t .. " dies;" end
	if tr[FAILS_SAVE] then t = t .. " fails a save;" end
	if tr[PASS_SAVE] then t = t .. " succeeds on a save;" end
	if tr[HEAL] then t = t .. " regains hp;" end
	if tr[STARTS_TURN] then t = t .. " starts its turn;" end
	if tr[ATK_FAIL] then t = t .. " fails attack roll;" end
	if tr[ATK_HITS] then t = t.. " succeeds on an attack roll;" end
	if tr[CAST] then t = t .. " casts a spell;" end
	if tr[BLOODIED] then t = t .. " becomes bloodied;" end
	if tr[FAILS_ATTR] then t = t .. " fails an attribute check;" end
	if tr[PASS_ATTR] then t = t .. " succeeds on an attribute check;" end
	if rReact.nDistEnemy ~= nil then t = t .. string.format(" enemy within %d feet;", rReact.nDistEnemy)
	elseif rReact.nDistAlly ~= nil then t = t .. string.format(" within %d feet;", rReact.nDistAlly) end
	if rReact.nACBonus ~= nil then t = t .. string.format(" AC bonus +%d;", rReact.nACBonus) end
	msg.text = t
	Comm.deliverChatMessage(msg)
end

function sendWarningMessage(rTarget, eff)
	if OptionsManager.getOption("REPRO_EFFECT_WARN") == "off" then return end
	local msg = ChatManager.createBaseMessage(rTarget)
	if OptionsManager.getOption("REPRO_RECIPIENT") == "gm" then msg.secret = true end
	msg.icon = "cond_stun"
	msg.text = "reaction impossible: creature"
	if eff.hasReacted then msg.text = msg.text .. " already reacted"
	else
		if eff.isUnconscious then msg.text = msg.text .. " is unconscious;" end
		if eff.isStunned then msg.text = msg.text .. " is stunned;" end
		if eff.isParalyzed then msg.text = msg.text .. " is paralyzed;" end
		if eff.isIncapacitated then msg.text = msg.text .. " is incapacitated;" end
		if eff.isPetrified then msg.text = msg.text .. " is petrified;" end
		if eff.isBlinded then msg.text = msg.text .. " must see the target but is blinded" end
		if eff.isInvisible then msg.text = msg.text .. " must see the target but it's invisible" end
	end
	Comm.deliverChatMessage(msg)
end

function parseReaction(sName, aActorName, aPowerWords)
	local rReact = {isSelf=true}
	local aTrigger = {}
	aBag = makeAppearanceMap(aPowerWords, 50)
	local l,r,f = findEnemyAttacks(aBag, aActorName)
	if f then
		parseAttackRange(aBag, l, r, aTrigger)
		parseAttackResult(aBag, l, r, aTrigger)
		parseDistance(aBag, aPowerWords, rReact)
	end
	if not f then l,r,f = findMonsterIsAttacked(aBag, aActorName)
		if f then
			parseAttackRange(aBag, l, r, aTrigger)
			parseAttackResult(aBag, l, r, aTrigger)
			parseACBonus(aBag, aPowerWords, rReact)
		end
	end
	if not f then l,r,f = findMonsterTakesCrit(aBag, aActorName)
		if f then aTrigger[CRIT] = true end
	end
	if not f then l,r,f = findMonsterFailsAttack(aBag, aActorName)
		if f then aTrigger[ATK_FAIL] = true end
	end
	if not f then l,r,f = findMonsterDamagedByAttack(aBag, aActorName)
		if f then
			aTrigger[DAMAGE] = true
			aTrigger[IS_HIT] = true
			parseAttackRange(aBag, l, r, aTrigger)
		
		end
	end
	-- deliberately put before findMonsterDamaged
	if not f then l,r,f = findOtherDamaged(aBag, aActorName)
		if f then
			parseDistance(aBag, aPowerWords, rReact, true)
			aTrigger[DAMAGE] = true
			rReact.isOther = true; rReact.isSelf = false
		end
	end
	if not f then l,r,f = findMonsterDamaged(aBag, aActorName)
		if f then
			_, _, orCreature = sequencePos(aBag, {aActorName, "or", "creature"})
			if not orCreature then  _, _, orCreature = sequencePos(aBag, {"creature", "or", aActorName}) end
			aTrigger[DAMAGE] = true
			if orCreature then rReact.isOther = true; parseDistance(aBag, aPowerWords, rReact, true) end
		end
	end
	if not f then l,r,f = findMonsterKills(aBag, aActorName)
		if f then aTrigger[KILLS] = true end
	end
	if not f then l,r,f = findMonsterDies(aBag, aActorName)
		if f then aTrigger[DIES] = true end
	end
	if not f then l,r,f = findWouldBeHit(aBag, aActorName)
		if f then
			aTrigger[IS_HIT] = true
			parseAttackRange(aBag, l, r, aTrigger)
			parseACBonus(aBag, aPowerWords, rReact)
		end
	end
	if not f then l,r,f = findOtherIsHit(aBag, aActorName)
		if f then
			parseAttackRange(aBag, l, r, aTrigger)
			parseAttackResult(aBag, l, r, aTrigger)
			parseDistance(aBag, aPowerWords, rReact, true)
			parseACBonus(aBag, aPowerWords, rReact)
			rReact.isOther = true; rReact.isSelf = false
		end
	end
	if not f then l,r,f = findOtherDies(aBag, aActorName)
		if f then
			parseDistance(aBag, aPowerWords, rReact, true)
			aTrigger[DIES] = true
			rReact.isOther = true; rReact.isSelf = false
		end
	end
	if not f then l,r,f = findOtherKills(aBag, aActorName)
		if f then
			parseDistance(aBag, aPowerWords, rReact, true)
			aTrigger[KILLS] = true
			rReact.isOther = true; rReact.isSelf = false
		end
	end
	if not f then l,r,f = findOtherFailsSave(aBag, aActorName)
		if f then
			parseDistance(aBag, aPowerWords, rReact, true)
			aTrigger[FAILS_SAVE] = true
			rReact.isOther = true; rReact.isSelf = false
		end
	end
	if not f then l,r,f = findEnemyCastsSpell(aBag, aActorName)
		if f then
			parseDistance(aBag, aPowerWords, rReact)
			aTrigger[CAST] = true
			rReact.isOther = true
		end
	end
	-- When another creature within 60 feet of the commander who can hear and understand them
	-- makes a saving throw, the commander can give that creature advantage on the saving throw.
	if not f then l,r,f = enemyAttacksAllies(aBag, aActorName)
		if f then
			parseAttackRange(aBag, l, r, aTrigger)
			parseAttackResult(aBag, l, r, aTrigger)
			parseDistance(aBag, aPowerWords, rReact)
			rReact.isOther = true; rReact.isSelf = false
		end
	end
	if not f then l,r,f = selfOrAllyAttacked(aBag, aActorName)
		if f then
			aTrigger[IS_HIT] = true; aTrigger[ATK_MELEE] = true; aTrigger[ATK_RANGED] = true
			rReact.isOther = true; rReact.isSelf = true
			parseDistance(aBag, aPowerWords, rReact, true)
		end
	end
	if not f then l,r,f = sequencePos(aBag, {"creature","regains","hit","points"})
		if f then
			aTrigger[HEAL] = true
			rReact.isOther = true; rReact.isSelf = false
			parseDistance(aBag, aPowerWords, rReact)
		end
	end
	if not f then l,r,f = findMonsterBloodied(aBag)
		if f then aTrigger[BLOODIED] = true end
	end
	parseVisionAndDamage(aBag, l, r, aPowerWords, aTrigger, rReact)
	rReact.aTrigger = aTrigger
	return rReact
end

function parseVisionAndDamage(aBag, l, r, aPowerWords, aTrigger, rReact)
	if next(aTrigger) ~= nil then
		parseVision(aBag, l, r, aTrigger)
		if aTrigger[DAMAGE] then rReact.aDamageTypes = parseDamageType(aPowerWords, l, r) end
	end
end

function parseTrait(sName, aActorName, aPowerWords)
	if isStandard(sName, aPowerWords) then
		return {}
	end
	local rReact = {isSelf=true, isPassive=true, isUnconditional=true}
	local aTrigger = {}
	aBag = makeAppearanceMap(aPowerWords, 40)
	local l,r,f = findMonsterDies(aBag, aActorName)
	if f then
		local _, _, isCondition = findNotIncapacitated(aBag)
		if isCondition then rReact.isUnconditional = nil end
		aTrigger[DIES] = true
	end
	if not f then l,r,f = findMonsterKills(aBag, aActorName)
		if f then aTrigger[KILLS] = true end
	end
	if not f then l,r,f = sequencePos(aBag, {"creature","touches","hits","attack"})
		if not f then l,r,f = sequencePos(aBag, {"whenever","hits","attack","damage"}) end
		if not f then l,r,f = sequencePos(aBag, {"whenever","hits","attack"}) end
		if f then
			aTrigger[IS_HIT] = true
			parseAttackRange(aBag, l, r, aTrigger)
			parseDistance(aBag, aPowerWords, rReact)
		end
	end
	if not f then l,r,f = findMonsterFailsSave(aBag, aActorName)
		if f then aTrigger[FAILS_SAVE] = true end
	end
	if not f then l,r,f = sequencePos(aBag, {"creature","starts",{"its","their"},"turn"})
		if f then
			local _, _, isCondition = findNotIncapacitated(aBag)
			if isCondition then rReact.isUnconditional = nil end
			aTrigger[STARTS_TURN] = true
			rReact.isOther = true; rReact.isSelf = false
			parseDistance(aBag, aPowerWords, rReact, true)
		end
	end
	-- Order is important since: "a creature that touches ... takes damage" or "when fails a save .. takes damage"
	if not f then l,r,f = findMonsterDamaged(aBag, aActorName)
		if f then aTrigger[DAMAGE] = true end
	end
	if not f then l,r,f = findMonsterBloodied(aBag)
		if f then aTrigger[BLOODIED] = true end
	end
	parseVisionAndDamage(aBag, l, r, aPowerWords, aTrigger, rReact)
	rReact.aTrigger = aTrigger
	return rReact
end

local standardTraits = {avoidance=true,evasion=true,["magic resistance"]=true,["gnome cunning"]=true,["magic weapons"]=true,
	["hellish weapons"]=true,["angelic weapons"]=true,["improved critical"]=true,["superior critical"]=true,regeneration=true,
	["innate spellcasting"]=true,spellcasting=true,minion=true,incorporeal=true,["sunlight hypersensitivity"]=true,
	["detect life"]=true}

function isStandard(sName, aPowerWords)
	if standardTraits[sName] then return true end
	if string.find(sName, "charge") or string.find(sName, "pounce") then
		return true
	end
end

function parseSpell(sName, aActorName, aPowerWords)
	aBag = makeAppearanceMap(aPowerWords, 20)
	local rReact = {isSelf=true}
	if not hasWordsWithin(aBag, 0, 20, {"reaction", "which", "you", "take"}) then
		return rReact
	end
	aBag = makeAppearanceMap(aPowerWords, 45, aBag["take"])
	local aTrigger = {}
	local l,r,f = sequencePos(aBag, {"when", "damage"}) -- Absorb Elements
	if f then
		aTrigger[DAMAGE] = true
		parseVisionAndDamage(aBag, l, r, aPowerWords, aTrigger, rReact)
	end
	if not f then l,r,f = sequencePos(aBag, {"when", "creature", "casting", "spell"}) -- Counterspell
		if f then
			aTrigger[CAST] = true
			rReact.isOther = true; rReact.isSelf = false
			parseVision(aBag, l, r, aTrigger)
		end
	end
	if not f then l,r,f = findMonsterDamaged(aBag, {"you"}) -- Hellish Rebuke
		if f then
			aTrigger[DAMAGE] = true
			parseVisionAndDamage(aBag, l, r, aPowerWords, aTrigger, rReact)
		end
	end
	if not f then l,r,f = sequencePos(aBag, {"when", "you", {"hit", "missed", "targeted"}, "attack"}) -- Shield
		if f then
			parseAttackRange(aBag, l, r, aTrigger)
			parseAttackResult(aBag, l, r, aTrigger)
			parseACBonus(aBag, aPowerWords, rReact)
		end
	end
	if not f then l,r,f = sequencePos(aBag, {"when", {"creature", "humanoid"}, "dies"}) -- Soul Cage
		if f then
			aTrigger[DIES] = true
			rReact.isOther = true; rReact.isSelf = false
			parseVision(aBag, l, r, aTrigger)
		end
	end
	if not f then l,r,f = sequencePos(aBag, {"when", "creature", "succeeds", "attack", "ability", "saving"}) -- Silvery Barbs
		if f then
			aTrigger={[ATK_HITS]=true;[PASS_ATTR]=true;[PASS_SAVE]=true}
			rReact.isOther = true; rReact.isSelf = false
			parseDistance(aBag, aPowerWords, rReact)
			parseVision(aBag, l, r, aTrigger)
		end
	end
	parseDistance(aBag, aPowerWords, rReact)
	rReact.aTrigger = aTrigger
	return rReact
end

local creatureTypes = {}
function creatureTypesList()
	if next(creatureTypes) == nil then
		for _,v in ipairs(DataCommon.creaturetype) do table.insert(creatureTypes, v) end
		for _,v in ipairs(DataCommon.creaturesubtype) do table.insert(creatureTypes, v) end
		table.insert(creatureTypes, "hobgoblin") -- technically those are 'goblinoids' but they referred by the species name in some reactions
		table.insert(creatureTypes, "goblin")
	end
	return creatureTypes
end

local enemy = {"creature", "enemy", "attacker"}
local hitsOrMisses = {"hits", "misses", "targets"}
local otherOrAlly = {"another","other","ally","allies"}
-- When a creature within 120 feet of Forzaantirilys attacks her,
function findEnemyAttacks(aBag, aName)
	local monster = {"it","him","her","them", unpack(aName)}
	local l,r,f = sequencePos(aBag, {enemy, "within", "feet", monster, hitsOrMisses, "attack"})
	if not f then l,r,f = sequencePos(aBag, {enemy, "within", "feet", aName, "attacks", {"it", "him", "her", "them"}}) end
	if not f then l,r,f = sequencePos(aBag, {enemy, hitsOrMisses, monster, "attack"}) end
	if not f then l,r,f = sequencePos(aBag, {enemy, monster, "can", "see", hitsOrMisses, "attack"}) end
	if not f then l,r,f = sequencePos(aBag, {enemy, "attacks", monster}) end
	if not f then l,r,f = sequencePos(aBag, {enemy, "makes", "attack", "against", monster}) end
	if f and hasNoneWithin(aBag, 0, r, otherOrAlly) then return l,r,f end
	return 0, 0, false
end

local isHit = {"hit", "struck", "missed", "targeted"}
function findMonsterIsAttacked(aBag, aName)
	local monster = {"it","him","her","them", unpack(aName)}
	-- sometimes monster name does not match, 'Cryomancer' may be called 'wizard' etc.
	local l,r,f = sequencePos(aBag, {{"when", "if"}, {"the", monster}, isHit, "attack"})
	-- "when targeted by an attack, M"
	if not f then l,r,f = sequencePos(aBag, {{"when", "if"}, isHit, "attack", aName}) end
	if f and hasNoneWithin(aBag, 0, r, {"creature", unpack(otherOrAlly)}) then return l,r,f end
	return 0, 0, false
end

function findMonsterTakesCrit(aBag, aName)
	local l,r,f =  sequencePos(aBag, {enemy, "scores", "critical", "against"})
	if not f then l,r,f = sequencePos(aBag, {aName, "suffers", "critical"}) end
	return l,r,f
end

function findMonsterFailsAttack(aBag, aName)
	local monster = {"it", "he", "she", "they", unpack(aName)}
	local l,r,f = sequencePos(aBag, {monster, "fails", "attack", "roll"})
	if not f then l,r,f = sequencePos(aBag, {monster, "misses", "attack"})
	end
	return l,r,f
end

function findMonsterDamagedByAttack(aBag, aName)
	local l,r,f = sequencePos(aBag, {"damaged", "by", "attack"})
	if not f then l,r,f = sequencePos(aBag, {aName, "takes", "damage", "from", "attack"}) end
	if f and hasNoneWithin(aBag, 0, r, otherOrAlly) then return l,r,f end
	return 0, 0, false
end

function findMonsterDamaged(aBag, aName)
	local l,r,f = sequencePos(aBag, {aName, "subjected", "to", "damage"})
	if not f then l,r,f = sequencePos(aBag, {"damaged", "by", "creature", "within", "feet", aName}) end
	if not f then l,r,f = sequencePos(aBag, {aName, "takes", "damage"}) end
	if not f then l,r,f = sequencePos(aBag, {enemy, "deals", "damage", {"it","him","her","them", unpack(aName)}}) end
	if not f then l,r,f = sequencePos(aBag, {enemy, aName, "can", "see", "deals", "damage"}) end
	if not f then l,r,f = sequencePos(aBag, {"after", "taking", "damage", "attack"}) end
	if not f then l,r,f = sequencePos(aBag, {aName, "is", "dealt", "damage"}) end
	if f and hasNoneWithin(aBag, 0, r, otherOrAlly) then return l,r,f end
	return 0, 0, false
end

function findMonsterDies(aBag, aName)
	local l,r,f = sequencePos(aBag, {{"if", "when"}, aName, "dies"})
	if not f then l,r,f = sequencePos(aBag, {"the", aName, {"reduced", "drops"}, {"0", "zero"}}) end
	if not f then l,r,f = sequencePos(aBag, {{"it", "he", "she"}, "dies", aName}) end
	if not f then l,r,f = sequencePos(aBag, {enemy, "within", aName, "reduces", {"0", "zero"}}) end
	if not f then l,r,f = sequencePos(aBag, {enemy, "reduces", aName,  {"0", "zero"}}) end
	if f and hasNoneWithin(aBag, 0, r, {"who", unpack(otherOrAlly)}) then return l,r,f end
	return 0, 0, false
end

-- When the crone kills a Humanoid, she can immediately
function findMonsterKills(aBag, aName)
	local l,r,f = sequencePos(aBag, {aName, "kills"})
	if not f then l,r,f = sequencePos(aBag, {aName, "reduces", {"0", "zero"}}) end
	if f and hasNoneWithin(aBag, 0, r, otherOrAlly) then return l,r,f end
	return 0, 0, false
end

function findMonsterFailsSave(aBag, aName)
	return sequencePos(aBag, {aName, "fails", "saving", "throw"})
end

function findWouldBeHit(aBag)
	return sequencePos(aBag, {"against", "attack", "that", "would", "hit"})
end

function findOtherIsHit(aBag, aName)
	return sequencePos(aBag, {{"creature", unpack(otherOrAlly)}, isHit, {"by", "with"}, "attack"})
end

-- When a non-minion hobgoblin who Varrox can see within 60 feet of him takes damage,
function findOtherDamaged(aBag, aName)
	local l,r,f = sequencePos(aBag, {otherOrAlly, "takes", "damage"})
	if not f then l,r,f = sequencePos(aBag, {creatureTypesList(), "takes", "damage"}) end
	return l,r,f
end

-- When an Undead under the vetala'a control is reduced to 0 hp, the vetala can force it to explode.
-- In response to a gnoll being reduced to 0 hit points
function findOtherDies(aBag, aName)
	local l,r,f = sequencePos(aBag, {otherOrAlly, "dies"})
	if not f then l,r,f = sequencePos(aBag, {otherOrAlly, {"reduced", "drops"}, {"0", "zero"}}) end
	if not f then l,r,f = sequencePos(aBag, {"creature", aName, "see", "dies"}) end
	if not f then l,r,f = sequencePos(aBag, {creatureTypesList(), "dies"}) end
	if not f then l,r,f = sequencePos(aBag, {creatureTypesList(), {"reduced", "drops"}, {"0", "zero"}}) end
	return l,r,f
end

function findOtherKills(aBag, aName)
	local l,r,f = sequencePos(aBag, {otherOrAlly, "kills"})
	if not f then l,r,f = sequencePos(aBag, {otherOrAlly, "reduces", {"0", "zero"}}) end
	return l,r,f
end

function findOtherFailsSave(aBag, aName)
	return sequencePos(aBag, {otherOrAlly, "fails", "saving", "throw"})
end

function findEnemyCastsSpell(aBag, aName)
	return sequencePos(aBag, {enemy, "casts", "spell"})
end

function enemyAttacksAllies(aBag, aName)
	local l,r,f = sequencePos(aBag, {enemy, aName, "see", "attacks", otherOrAlly})
	if not f then l,r,f = sequencePos(aBag, {enemy, hitsOrMisses, otherOrAlly, "attack"}) end
	return l,r,f
end

function selfOrAllyAttacked(aBag, aName)
	local l,r,f = sequencePos(aBag, {aName, "creature", "attacked"})
	if not f then l,r,f = sequencePos(aBag, {"creature", aName, "attacked"}) end
	return l,r,f
end

function findMonsterBloodied(aBag)
	local l,r,f = sequencePos(aBag, {"first", "bloodied"})
	if not f then l,r,f = sequencePos(aBag, {"reduced", "half", "hit", "points"}) end
	return l,r,f
end

function findNotIncapacitated(aBag)
	return sequencePos(aBag, {{"isn't", "aren't", "weren't", "wasn't", "not"}, "incapacitated"})
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
	local miss = {"misses","miss","missed"}
	if hasNoneWithin(aBag, l, r, {"hits","hit","struck", unpack(miss)}) then
		aTrigger[IS_MISSED] = true
		aTrigger[IS_HIT] = true
	else
		if hasOneOfWithin(aBag, l, r, {"hits","hit", "struck"}) then aTrigger[IS_HIT] = true end
		if hasOneOfWithin(aBag, l, r, miss) then aTrigger[IS_MISSED] = true end
	end
end

function parseVision(aBag, l, r, aTrigger)
	if hasWordsWithin(aBag, l, r, {"can","see"}) or hasWordsWithin(aBag, l, r, {"able","to","see"}) or hasWordsWithin(aBag, l, r, {"see", "creature"}) then aTrigger[VISION] = true end
end

function parseDamageType(aPowerWords, l, r)
	aDamageTypes = {}
	i = r
	while i > l and not StringManager.isWord(aPowerWords[i], {"takes", "subjected"}) do if StringManager.isWord(aPowerWords[i], DataCommon.dmgtypes) then table.insert(aDamageTypes, aPowerWords[i]) end
		i = i - 1
	end
	return aDamageTypes
end

function parseDistance(aBag, aWords, rReact, isAlly)
	local _, r, f = sequencePos(aBag, {"within", "feet"})
	if not f then return end
	if isAlly then rReact.nDistAlly = tonumber(aWords[r-1]) else rReact.nDistEnemy = tonumber(aWords[r-1]) end
end

function parseACBonus(aBag, aWords, rReact)
	local nACPos = 0
	local l, _, f = sequencePos(aBag, {{"gains", "gain", "have"}, "bonus", "ac"})
	if f then nACPos = l + 2
	else
		l, _, f = sequencePos(aBag, {"add", "to", "ac"})
		if f then nACPos = l + 1 end
	end
	if nACPos ~= 0 then rReact.nACBonus = tonumber(aWords[nACPos]); end
end

function makeAppearanceMap(aPowerWords, nLim, nOffset)
	result = {}
	if nOffset == nil then nOffset = 0 end
	for i, w in ipairs(aPowerWords) do
		--uncomment to remove "'s" like in "balor's"
		--if #w > 2 and w:sub(#w-1, #w-1) == "'" then w = w:sub(0, -2) end
		if i > nOffset then
			if result[w] == nil then result[w] = i end
			if nLim ~= nil and i > nLim + nOffset then return result end
		end
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
-- Keep in mind that the function checks FIRST APPEARANCE of a word, so a search:
-- {"whenever", "hits", "damage"} with input
-- "creature .. takes lightning damage whenever it hits the M with an attack that deals slashing damage"
-- will not work, because the word "damage" appears earlier than 'whenever'
function sequencePos(aBag, aSeq)
	local nFirst = 0
	local nLast = 0
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
