# Prompt-Reaction
This is an extension for Fantasy Grounds VTT written in Lua.

## What does it do

This extension parses NPCs added in the Combat Tracker and detects what reactions they have. When the corresponding trigger happens, and the creature is able to react i.e. it is not incapacitated, did not spend its reaction and can see the target if vision is required, a prompt will appear in the chat. The prompt can be a link to the reaction, a link to the NPC sheet or the description of the reaction itself.

Besides incapacitation, the extension will check if the distance is right provided that you use a grid and it's open.

"Parry" - type abilities that allow you to add a bonus to monsters AC as a reaction have additional automation - the extension will tell you whether adding the bonus will deflect attack or not.

The extension can detect and process not only simple triggers like “this creature is hit” but also “third-party” triggers like “a creature starts its turn near the monster” or “monster’s ally is killed”. Specifically, it can detect:
* An attack on the monster hits or misses (attack type, melee or ranged is also recognized).
  * There are many recognized formulas: "when a creature within X feet (hits | misses | targets) (monster_name | it | him | her) with an (melee | ranged) attack"; "enemy hits the monster with an attack; "a creature attacks the monster"; "a creature makes attack against the monster"; "if the monster is (hit | missed | targeted) with an (melee | ranged) attack"; "when hit by an attack, the monster doex X"...
* An attack on the monster’s allies hits or misses.
  * "(another creature | an ally) is (hit | missed | targeted) by an attack"; "a creature (hits | misses | targets) an ally with an attack".
* The monster takes damage (of type X, type is parsed).
  * There are also numerous possible wordings: "the monster_name is damaged by an attack"; "the monster takes (damage_type) damage"; "the monster is subjected to (type) damage"; "enemy deals damage to the monster"; "the monster is dealt damage"...
* The monster dies.
  * Examples are: "the monster_name dies"; "the monster is reduced to 0 hit points"; "a creature reduces the monster to 0 hit points"; "the monster drops to 0 hit points"...
* An ally takes damage (of type X, type is parsed).
  * "(other creature | an ally | creature other than the monster ) takes damage".
* An ally dies
  * "(an ally | another creature) (dies | drops to 0 hit points | is reduced to 0".
* Monster kills a creature.
  * "the monster (kills|reduces to 0 hit points)"
* Creature starts its turn. (Only triggered by PCs)
* The monster or an ally fails a saving throw.
* The monster suffers a crit.
  * Typical wording is "when a creature scores a critical hit against the monster_name" or "when the monster_name suffers a critical hit".
* Monster fails an attack.
  * Typical wording is "when the monster_name fails an attack roll" or "monster_name misses with a(n) (melee|ranged) attack"
* Creature regains hit points.

The extension currently cannot process:
* Spells. Specifically triggers like “creature casts a spell”. Currently not triggered.
* Creature types, for example “a gnoll within 60 feet of the monster dies”, this creature type is not considered for triggering reactions (any creature that dies will trigger the reaction).
* Movement. “When a creature within 30 feet of the monster moves…”. Such reactions cannot be detected in the current version.

## Configuration options

**Notification recipients**: (everyone | GM only) When GM only is selected, players will not see the reaction prompts or warnings when a condition prevents a monster from reacting.


**Report parsing results**: (on | off) When turned on, the extension will output to the chat the reactions it detects for the NPC when it is added to CT and corresponding trigger conditions. These messages are always visible only to the GM.


**Select message format**: (Reaction link | NPC link | Reaction text | off) When turned off, no prompts will be sent. Other options are self-explanatory.


**Warn if an effect prevents reaction**: (on | off) When turned on, messages will be sent to the chat if a reaction could be triggered, but an incapacitated condition prevents the monster from reacting, of when the monster must see its target, but the target is invisible or the monster is blinded, or if the monster already spend its reaction (“reaction” checkbox is ticked on the monster record in the CT).


**Notify for hidden tokens**: (on | off) When turned off, reaction notifications will not be triggered for hidden tokens.


**Notify in hidden Combat Groups**: (on | off) Compatibility option for "Combat Groups" extension. When turned off (default), no reaction notifications will be shown for combatants in hidden groups.


## How does it work

After FG launches, the extension scans the Combat Tracker records and indexes the reactions in them. It happens only once and triggered the first time you either:
* Click “Next Turn”
* Add an NPC into the tracker
* Make an attack
* Force a saving throw
* Deal damage
After that each NPC that is added to the tracker is scanned individually and added to the index. This index allows to detect situations in which a creature other than targeted by the players can react. When an NPC is removed from the tracker, its reactions are removed as well.

## Legal notes and art credits

Fantasy Grounds is copyright SmiteWorks USA LLC, 2004-2023. All Rights Reserved.
	
No core Fantasy Grounds files have been modified to create this extension.
If you want to incorporate this into one of your own extensions, have at it, but just credit me.

Credit for the icon goes to flaticon.com who generously allow free use with attribution:
[Return icons created by Kiranshastry - Flaticon](https://www.flaticon.com/free-icons/return)
