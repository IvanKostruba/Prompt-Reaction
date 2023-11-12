# Prompt-Reaction
This is an extension for Fantasy Grounds VTT written in Lua.

## What does it do

This extension parses NPCs added in the Combat Tracker and detects what reactions they have. When the corresponding trigger happens, and the creature is able to react i.e. it is not incapacitated, did not spend its reaction and can see the target if vision is required, a prompt will appear in the chat. The prompt can be a link to the reaction, a link to the NPC sheet or the description of the reaction itself.

The extension can detect and process not only simple triggers like “this creature is hit” but also “third-party” triggers like “a creature starts its turn near the monster” or “monster’s ally is killed”. Specifically, it can detect:
* An attack on the monster hits or misses (attack type, melee or ranged is also recognized).
* An attack on the monster’s allies hits or misses.
* The monster takes damage [of type X] or dies.
* An ally takes damage or dies.
* Monster kills a creature.
* Creature starts its turn.
* The monster or an ally fails a saving throw.

The extension currently cannot process:
* Spells. Specifically triggers like “creature casts a spell”. Currently not triggered.
* Creature types, for example “a gnoll within 60 feet of the monster dies”, this creature type is not considered for triggering reactions (any creature that dies will trigger the reaction).
* Distances. When the reaction says “a creature within N feet from the monster does X”. The distance will not be considered for trigger matching, so any creature that does X will trigger the message.
* Movement. “When a creature within 30 feet of the monster moves…”. Such reactions cannot be detected in the current version.

## Configuration options

**Notification recipients**: (everyone | GM only) When GM only is selected, players will not see the reaction prompts or warnings when a condition prevents a monster from reacting.

**Report parsing results**: (on | off) When turned on, the extension will output to the chat the reactions it detects for the NPC when it is added to CT and corresponding trigger conditions. These messages are always visible only to the GM.

**Select message format**: (Reaction link | NPC link | Reaction text | off) When turned off, no prompts will be sent. Other options are self-explanatory.

**Warn if an effect prevents reaction**: (on | off) When turned on, messages will be sent to the chat if a reaction could be triggered, but an incapacitated condition prevents the monster from reacting, of when the monster must see its target, but the target is invisible or the monster is blinded, or if the monster already spend its reaction (“reaction” checkbox is ticked on the monster record in the CT).

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
