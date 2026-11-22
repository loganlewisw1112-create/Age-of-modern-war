extends RefCounted
## G5 (UI5b) hotkey map for every command-card action, with user rebinding (G5 actions).
## One table, read by the card buttons (g4b_commands / g5_unit_cmds / airfield_panel), the settings
## menu (key rebinding), the F1 sheet and tests/test_ui_panels.gd (collision check).
##
## Keys are upper-case OS.get_keycode_string names ("Z", "TAB"). Rules:
##   - GLOBAL keys (match view / HUD) are never used by a card action.
##   - FIXED actions are the G1-G4 card keys (Stop/Hold/Patrol/...); they are not rebindable.
##   - Within a group, and between groups that can share one card (SHARE), keys are unique.
##     Groups that never share a card (drone vs tactical mode of one Drone Team, aircraft vs a
##     building card) may reuse letters.
## User bindings live in Settings (presentation/menu/settings.gd, section "keys"); Hotkeys.key()
## reads them through the static cache below, so a rebind applies on the next card rebuild.

const GLOBAL := {
	"A": "Attack-move (then click)", "P": "Pause / resume", "W": "Pan up", "D": "Pan right",
	"SPACE": "Jump to the last alert", "PERIOD": "Next idle worker", "F1": "Hotkey sheet",
	"ESCAPE": "Cancel / pause menu", "TAB": "Next build category (Shift+Tab: previous)",
	"1": "Group 1", "2": "Group 2", "3": "Group 3", "4": "Group 4", "5": "Group 5",
	"6": "Group 6", "7": "Group 7", "8": "Group 8", "9": "Group 9", "0": "Group 0",
	"F5": "Quick save", "F9": "Quick load",
	"F2": "Teams panel", "F3": "Command mode (plans on the map)",   # G6.1 (SQUAD61 / PLAN61)
}

## G6.1 (SQUAD61): HUD-wide actions with a GLOBAL key (not rebindable here): action -> [key, label].
const GLOBAL_ACTIONS := {"teams_panel": ["F2", "Teams panel"], "command_mode": ["F3", "Command mode (plans on the map)"],
	"ops_room": ["F4", "Operations room (teams, deployments, team cam, map, war table, codex)"]}  # G7 OPSUI7 CR 1404
## Printable badge for a non-letter key name.
const BADGE := {"COMMA": ",", "SEMICOLON": ";", "SLASH": "/", "APOSTROPHE": "'", "BRACKETLEFT": "[",
	"BRACKETRIGHT": "]", "BACKSLASH": "\\", "MINUS": "-", "EQUAL": "=", "BACKSPACE": "Bksp", "QUOTELEFT": "`"}
## Keys the squad61 card actions may be rebound to (letters are all taken by unit-card actions).
const PUNCT_KEYS := ["COMMA", "SEMICOLON", "SLASH", "APOSTROPHE", "BRACKETLEFT", "BRACKETRIGHT", "BACKSLASH", "MINUS", "EQUAL"]

## G1-G4 card actions (fixed): action -> [key, label]
const FIXED := {
	"stop": ["S", "Stop"], "hold": ["H", "Hold position"], "patrol": ["Q", "Patrol"],
	"guard": ["G", "Guard"], "formation": ["F", "Formation"], "deploy": ["E", "Deploy / pack"],
	"lay_mine": ["M", "Lay mine"], "plant_charge": ["O", "Plant charge"],
	"unload_point": ["I", "Unload at point"], "unload_all": ["L", "Unload all / lock gate"],
	"repair": ["R", "Repair"],
}

## G5 actions (rebindable): action -> [default key, label, group, command]
const ACTIONS := {
	"sortie": ["T", "Sortie (strike)", "air", "sortie"],
	"rebase": ["B", "Rebase", "air", "rebase"],
	"land_at": ["N", "Land here", "air", "land_at"],
	"take_off": ["U", "Take off", "air", "take_off"],
	"drone_strike": ["Z", "Strike drone", "drone", "launch_drone"],
	"drone_frag": ["X", "Frag drone", "drone", "launch_drone"],
	"drone_recon": ["C", "Recon drone", "drone", "launch_drone"],
	"drone_emp": ["V", "EMP drone", "drone", "launch_drone"],
	"tact_infiltrate": ["Z", "Infiltrate", "tactical", "tactical"],
	"tact_takedown": ["X", "Takedown", "tactical", "tactical"],
	"tact_breach": ["C", "Breach", "tactical", "tactical"],
	"tact_stack_up": ["V", "Stack up", "tactical", "tactical"],
	"tact_armored_attack": ["Y", "Armored attack", "tactical", "tactical"],
	"truck_auto": ["K", "Truck Auto resupply", "truck", "set_auto_resupply"],
	"medic_auto": ["J", "Medic Auto evac", "medic", "set_auto_evac"],
	"bombard": ["Y", "Bombard", "naval", "bombard"],
	"assign_engineers": ["N", "Assign engineers", "eng_air", "assign_engineers"],
	"hangar_light": ["J", "Buy light hangar", "airfield", "build_hangar"],
	"hangar_heavy": ["K", "Buy heavy hangar", "airfield", "build_hangar"],
	"extra_strip": ["N", "Add strip", "airfield", "upgrade_airfield"],
	"hangar_level": ["U", "Upgrade hangar", "hangar", "upgrade_hangar"],
	"hangar_to_heavy": ["Y", "Hangar to heavy", "hangar", "upgrade_hangar"],
	# G6 (UI6b) unit actions, armed / issued by presentation/ui6/b/g6_cmds.gd. Engineer-card keys
	# (minefield, sweep, rail, garrison, tow) are J/U/X/Z/C: no building data hotkey uses them and
	# G3.AVOID_KEYS keeps generated build keys off them, so the build page never steals them.
	"minefield": ["J", "Lay minefield", "mines6", "lay_minefield"],
	"sweep": ["U", "Sweep mines", "mines6", "sweep"],
	"line_charge": ["C", "Line charge", "mines6", "line_charge"],
	"build_rail": ["X", "Lay rail", "rail6", "build_rail"],
	"garrison": ["Z", "Garrison", "garrison6", "garrison"],
	"loadout": ["V", "Loadout", "loadout6", "set_loadout"],
	"designate": ["T", "Designate", "designate6", "designate"],
	"breach": ["B", "Breach", "breach6", "breach"],
	"cloak": ["N", "Cloak", "cloak6", "cloak"],
	"strike": ["K", "Strike", "strike6", "strike"],
	"deploy_bridge": ["B", "Deploy bridge", "bridge6", "deploy_bridge"],
	"pack_bridge": ["N", "Pack bridge", "bridge6", "pack_bridge"],
	"aerostat": ["Y", "Raise aerostat", "aerostat6", "aerostat"],
	"assimilate": ["Y", "Assimilate", "assim6", "assimilate"],
	"tow_wreck": ["Z", "Tow wreck", "tow6", "tow_wreck"],
	"airdrop": ["C", "Airdrop", "airdrop6", "airdrop"],
	"submerge": ["V", "Dive / surface", "sub6", "submerge"],
	"sea_mines": ["J", "Lay sea mines", "seamine6", "lay_sea_mines"],
	# G6 (UI6b) building-card actions
	"ungarrison": ["U", "Empty building", "garrison_bld6", "ungarrison"],
	"battery_strike": ["K", "Fire strike", "battery6", "strike"],
	"resuit": ["J", "Re-suit pilot", "garage6", "resuit"],
	# G6.1 (SQUAD61): on every combat unit card, so they use punctuation keys (group squad61 shares all unit cards)
	"stance_page": ["COMMA", "Stance (page)", "squad61", "set_stance"],
	"formations_page": ["SEMICOLON", "Formations (page)", "squad61", "set_formation"],
	"regroup": ["SLASH", "Regroup on leader", "squad61", "regroup"],
	# G6.1 (INTEG61, BEARER61 CR seq 332): ammo bearer card. J is taken (medic_auto / minefield / sea mines share
	# infantry cards) and the card ignores Shift, so the bearer actions use free punctuation keys [ and ].
	"bearer_join": ["BRACKETLEFT", "Join squad", "bearer61", "join_squad"],
	"bearer_leave": ["BRACKETRIGHT", "Leave squad", "bearer61", "leave_squad"],
}
## G7 actions (rebindable, same row format as ACTIONS; key() / label() / group() / collisions() cover them; kept out
## of ACTIONS so the G5 card probe in test_ui_panels does not demand a G5-style card button for each).
##   squad7: the formation page (it replaces the unit card, so only the page's own FORM_KEYS L E C B J K I X V N,
##           Z pace and Backspace share it: PAGE_GROUPS share with nothing else).
##   drone7: DRONE7's Drone Team card actions (shares the card with the drone and loadout6 groups and the fixed keys;
##           Space is a GLOBAL key and C/U were taken there, so drop = J, detonate = K, fullscreen = N).
const G7_ACTIONS := {
	"tech_auto": ["Y", "Auto technique", "squad7", "set_technique"],
	"tech_traveling": ["U", "Traveling", "squad7", "set_technique"],
	"tech_overwatch": ["T", "Traveling overwatch", "squad7", "set_technique"],
	"tech_bounding": ["R", "Bounding overwatch", "squad7", "set_technique"],
	"fall_back": ["M", "Fall back", "squad7", "fall_back"],
	"suppress": ["Q", "Suppress", "squad7", "suppress_area"],
	"clear_building": ["H", "Clear building", "squad7", "clear_building"],
	"drone_take": ["Y", "Take control (fly)", "drone7", "drone_take"],
	"drone_fullscreen": ["N", "Drone camera fullscreen", "drone7", "drone_view"],
	"drone_handback": ["B", "Hand back to AI", "drone7", "drone_release"],
	"drone_thermal": ["T", "Thermal view", "drone7", "drone_view"],
	"drone_drop": ["J", "Drop munition", "drone7", "drone_drop"],
	"drone_detonate": ["K", "Detonate", "drone7", "drone_detonate"],
	# G7 (WOUND7 CR seq 102, ORCH): casualty care on every infantry / medic / carrier card. Every plain letter is
	# taken on infantry cards, so these are Shift chords ("SHIFT+<key>"); hud.gd resolves them with event_key().
	"treat_casualty": ["SHIFT+T", "First aid: nearest wounded own soldier", "wound7", "treat_casualty"],
	"evacuate_casualty": ["SHIFT+E", "Evacuate casualty: ambulance / APC / helicopter / stretcher team, then a downed soldier", "wound7", "evacuate_casualty"],
	# G7 (CNSIM7-3 CR seq 557, SQUAD7-5): counter-nanite team orders. P is the GLOBAL pause key, so the pincer is the
	# Shift chord SHIFT+P (hud.gd resolves chords with event_key(); plain P still pauses).
	"cn_pincer": ["SHIFT+P", "Anti-walker pincer", "cn7", "cn_pincer"],
	"cn_break_contact": ["SHIFT+B", "Break contact (formed withdrawal)", "cn7", "cn_break_contact"],
	# G7.1 (AIRFIX71-2 CR seq 149, ORCH): draw a patrol loop for helicopters / VTOLs. SHIFT+P was asked for but cn_pincer
	# owns it and a mixed CN + air selection shows both cards, so the free chord SHIFT+Y is used.
	"air_patrol": ["SHIFT+Y", "Patrol route", "air", "air_patrol"],
	# G7.1 (FIRES71-3 CR seq 1830, ORCH decision PROVISIONAL): hold for the radial fire-support menu (presentation/ui71/
	# fire_radial.gd reads this action). F is the fixed Formation key, every free letter is taken: backquote / tilde.
	"fire_radial71": ["QUOTELEFT", "Fire support (hold)", "fires71", "fire_mission"],
	# G7 (CNOPS7 CR seq 1206, SQUAD7-6): CNOPS7 proposed Alt+F / Alt+R / Alt+U, but hud._unhandled_input drops every
	# key event with Alt / Ctrl / Meta held before the card lookup, so Alt chords can never fire; same letters as
	# Shift chords instead (free in cn7: only SHIFT+P / SHIFT+B there, wound7 SHIFT+T / SHIFT+E on every card).
	"cn_fire_support": ["SHIFT+F", "Call fire support (team leader)", "cn7", "cn_fire_support"],
	"cn_relief": ["SHIFT+R", "Send relief convoy", "cn7", "cn_relief"],
	"cn_specialize": ["SHIFT+U", "Specialist upgrade", "cn7", "cn_specialize"],
	# G7 CNMISSION8 (13.9c-44): PURGE MISSION + Team orders on the cn7 card (SHIFT+A / SHIFT+O, agreed with SPECOPS8 on
	# the board); the step buttons and Drive / Fly sit on their own sub-pages (page group cn8p, shares nothing).
	"cn_purge_mission": ["SHIFT+A", "Purge mission (click creep / core, then Drive or Fly)", "cn7", "cn_mission"],
	"cn_team_orders": ["SHIFT+O", "Strike team step orders (page)", "cn7", "cn_mission"],
	"cn_mission_drive": ["SHIFT+R", "Purge mission: drive", "cn8p", "cn_mission"],
	"cn_mission_fly": ["SHIFT+F", "Purge mission: fly (dropship)", "cn8p", "cn_mission"],
	"cn_mount_team": ["SHIFT+M", "Mount (board the APCs)", "cn8p", "cn_mount"],
	"cn_move_team": ["SHIFT+V", "Move team (click)", "cn8p", "cn_move"],
	"cn_dismount_team": ["SHIFT+D", "Dismount", "cn8p", "cn_dismount"],
	"cn_deploy_here": ["SHIFT+S", "Deploy package (click ground)", "cn8p", "cn_deploy"],
	"cn_hero_detonate": ["SHIFT+H", "Hero detonate", "cn8p", "cn_hero_detonate"],
	"cn_loadout_cycle": ["SHIFT+L", "Loadout (next preset)", "cn8p", "cn_set_loadout"],
	"cn_extract": ["SHIFT+X", "Extract / return home", "cn8p", "cn_extract"],
	"cn_mission_cancel": ["SHIFT+C", "Cancel purge mission", "cn8p", "cn_mission_cancel"],
	"cn_mission_hold": ["SHIFT+O", "Hold the purged site (toggle)", "cn8p", "cn_mission_hold"],
	# G7 (FISSURE7 CR 710, SQUAD7-6): engineers span a fissure / canyon (click a tile). FISSURE7 proposed J, but the
	# engineer card already holds J / U / X / Z (minefield, sweep, rail, garrison: the only letters the generated build
	# keys never take), so it is the Shift chord SHIFT+J (same mnemonic; plain J stays the minefield).
	"fissure_span": ["SHIFT+J", "Span fissure (engineers bridge a fissure / canyon)", "fissure7", "fissure_span"],
	# G7 (AIRV7, ORCH CR 4527 part 5): CN Vanta gunship card (shares the air card). Alt chords never reach the card
	# lookup (hud drops Alt), so Shift chords: H home pad, N nose, W wing / side pair, Q rear hardpoint.
	"vanta_rtb": ["SHIFT+H", "Return to roof pad", "vanta7", "vanta_rtb"],
	"vanta_cycle_nose": ["SHIFT+N", "Nose hardpoint (next item)", "vanta7", "vanta_loadout"],
	"vanta_cycle_side": ["SHIFT+W", "Side hardpoints, both sides (next item)", "vanta7", "vanta_loadout"],
	"vanta_cycle_rear": ["SHIFT+Q", "Rear hardpoint (next item)", "vanta7", "vanta_loadout"],
	# G7 SPECOPS8 (13.9c-44): spec-ops missions on the tactical operator squad card (shares the cn7 card; Shift chords
	# agreed with CNMISSION8: G C K M I Z here; SPREAD8: rescue moved Y -> M (medevac; X is a test rebind of cn_pincer), so Y stays free for rebinding the cn7 orders, A O on cn7, the rest on its cn8p page).
	"so_escort": ["SHIFT+G", "Spec ops: escort a purge mission (click the strike team)", "so8", "so_mission"],
	"so_raid": ["SHIFT+C", "Spec ops: core raid (click a core / Machine structure)", "so8", "so_mission"],
	"so_recon": ["SHIFT+K", "Spec ops: recon & mark (click an area)", "so8", "so_mission"],
	"so_rescue": ["SHIFT+M", "Spec ops: rescue / extract (click survivors or a beacon)", "so8", "so_mission"],
	"so_insert": ["SHIFT+I", "Spec ops: insert by Drive or Fly (toggle)", "so8", "so_mission"],
	"so_cancel": ["SHIFT+Z", "Spec ops: cancel the mission", "so8", "so_cancel"],
	# G7 CARDS8A (13.9c-48): building cards. cc8 = command centre / ops room card, def8 = defences card (turrets,
	# towers, CIWS, gates). Building cards never share a card with units or with each other, so they reuse letters.
	"cc_fire_art": ["B", "Fire support: artillery (then click a target)", "cc8", "cc_fire"],
	"cc_fire_rockets": ["K", "Fire support: rockets (then click a target)", "cc8", "cc_fire"],
	"cc_fire_air": ["N", "Fire support: air strike (then click a target)", "cc8", "cc_fire"],
	"cc_withdraw": ["X", "Withdraw: fighting withdrawal into the compound", "cc8", "cc_withdraw"],
	"cc_last_stand": ["Z", "Last stand: commit the reserve to the core doors", "cc8", "cc_last_stand"],
	"cc_mission_next": ["T", "Mission board: next mission", "cc8", "cc_mission"],
	"cc_mission_recall": ["C", "Mission board: recall the marked team", "cc8", "cn_extract"],
	"cc_mission_cancel": ["V", "Mission board: cancel the marked mission", "cc8", "cn_mission_cancel"],
	"def_fire_mode": ["T", "Fire mode: hold / return fire / fire at will (cycle)", "def8", "def_fire_mode"],
	"def_priority": ["Y", "Target priority: any / infantry / vehicles / air (cycle)", "def8", "def_priority"],
	"gate_open": ["U", "Gate: hold open", "def8", "gate_set"],
	"gate_close": ["J", "Gate: hold closed (opens only for its traffic)", "def8", "gate_set"],
	"gate_lock": ["K", "Gate: lock", "def8", "gate_set"],
	"gate_auto": ["N", "Gate: release to the automatic cycle", "def8", "gate_set"],
	"def_repair": ["X", "Repair / rearm now (nearest facility engineer)", "def8", "def_repair"],
	# G7 SUPPLY8 (13.9c-48): magazine / ammo + fuel bay card (group sup8; the card shows only while the magazine is
	# selected, nothing else binds keys then).
	"sup8_order": ["T", "Order airdrop delivery (retrieval op)", "sup8", "sup8_order"],
	"sup8_prio": ["Y", "Resupply priority: next class first (cycle)", "sup8", "sup8_prio"],
	"sup8_mix_type": ["C", "Ammo mix: next round type", "sup8", "sup8_mix"],
	"sup8_mix_up": ["V", "Ammo mix: +10% of the round type", "sup8", "sup8_mix"],
	"sup8_mix_down": ["X", "Ammo mix: -10% of the round type", "sup8", "sup8_mix"],
	# G7 CARDS8B (13.9c-48): Armory + Suit Foundry card (arm8b) and Garages / workshop / decon wash card (gar8b). Page
	# groups (shown only with their facility part selected, share no card), Shift chords like the other G8 cards.
	"arm8b_role": ["SHIFT+T", "Armory: next team role", "arm8b", "c8b_preset"],
	"arm8b_preset": ["SHIFT+L", "Armory: next loadout preset for the role", "arm8b", "c8b_preset"],
	"arm8b_suit_role": ["SHIFT+S", "Armory: next suit role", "arm8b", "c8b_suit_build"],
	"arm8b_build": ["SHIFT+B", "Armory: build suit", "arm8b", "c8b_suit_build"],
	"arm8b_rush": ["SHIFT+R", "Armory: rush the suit in production", "arm8b", "c8b_suit_rush"],
	"arm8b_repair": ["SHIFT+E", "Armory: repair damaged suits", "arm8b", "c8b_suit_repair"],
	"arm8b_up_pick": ["SHIFT+I", "Armory: next weapon upgrade", "arm8b", "c8b_upgrade"],
	"arm8b_upgrade": ["SHIFT+U", "Armory: research weapon upgrade", "arm8b", "c8b_upgrade"],
	"gar8b_team": ["SHIFT+T", "Garage: next vehicle team", "gar8b", "c8b_veh_repair"],
	"gar8b_repair": ["SHIFT+R", "Garage: priority repair (toggle)", "gar8b", "c8b_veh_repair"],
	"gar8b_up_pick": ["SHIFT+I", "Garage: next vehicle upgrade", "gar8b", "c8b_veh_upgrade"],
	"gar8b_upgrade": ["SHIFT+U", "Garage: fit vehicle upgrade", "gar8b", "c8b_veh_upgrade"],
	"gar8b_pick": ["SHIFT+V", "Garage: team in / out of the convoy", "gar8b", "c8b_convoy"],
	"gar8b_convoy": ["SHIFT+C", "Garage: launch convoy (click destination)", "gar8b", "c8b_convoy"],
	"gar8b_recall": ["SHIFT+H", "Garage: recall all home", "gar8b", "c8b_recall"],
	"gar8b_decon": ["SHIFT+D", "Garage: force decon", "gar8b", "c8b_decon_force"],
	"gar8b_skip": ["SHIFT+W", "Garage: skip wash under fire", "gar8b", "c8b_decon_skip"],
	# G7 CARDS8C (13.9c-48): Sentinel barracks (bar8c), helipads + VTOL pad (air8c), aid station (aid8c), package lab
	# (lab8c) cards. Page groups (each card shows alone, with its facility part selected), Shift chords.
	"bar8c_post": ["SHIFT+P", "Barracks: next watch post", "bar8c", "c8c_rotate"],
	"bar8c_rotate": ["SHIFT+R", "Barracks: rotate the post (fresh men relieve it)", "bar8c", "c8c_rotate"],
	"bar8c_role": ["SHIFT+T", "Barracks: next Sentinel role", "bar8c", "c8c_train"],
	"bar8c_train": ["SHIFT+B", "Barracks: train the role", "bar8c", "c8c_train"],
	"bar8c_plan": ["SHIFT+L", "Barracks: next patrol plan", "bar8c", "c8c_plan"],
	"bar8c_adopt": ["SHIFT+A", "Barracks: adopt the patrol plan", "bar8c", "c8c_plan"],
	"bar8c_standto": ["SHIFT+S", "Barracks: stand to (wake all)", "bar8c", "c8c_standto"],
	"air8c_pick": ["SHIFT+N", "Air: next aircraft", "air8c", "c8c_air_service"],
	"air8c_service": ["SHIFT+E", "Air: service at its own pad (rearm / refuel / repair)", "air8c", "c8c_air_service"],
	"air8c_launch": ["SHIFT+L", "Air: launch (click a point)", "air8c", "c8c_air_launch"],
	"air8c_launch_all": ["SHIFT+A", "Air: launch all (click a point)", "air8c", "c8c_air_launch"],
	"air8c_recall": ["SHIFT+H", "Air: recall all to their pads", "air8c", "c8c_air_recall"],
	"air8c_cap": ["SHIFT+P", "Air: air patrol (click a point)", "air8c", "c8c_air_cap"],
	"air8c_cap_end": ["SHIFT+X", "Air: end the air patrol", "air8c", "c8c_air_cap"],
	"aid8c_pick": ["SHIFT+N", "Aid station: next casualty", "aid8c", "c8c_cas_first"],
	"aid8c_first": ["SHIFT+F", "Aid station: treat first", "aid8c", "c8c_cas_first"],
	"aid8c_evac": ["SHIFT+E", "Aid station: evacuate", "aid8c", "c8c_evac"],
	"aid8c_medics": ["SHIFT+M", "Aid station: medics to a point (click)", "aid8c", "c8c_medics"],
	"lab8c_pkg": ["SHIFT+N", "Lab: next package", "lab8c", "cn_lab_queue"],
	"lab8c_queue": ["SHIFT+Q", "Lab: queue the package", "lab8c", "cn_lab_queue"],
	"lab8c_tier": ["SHIFT+U", "Lab: upgrade the lab tier", "lab8c", "cn_lab_upgrade"],
	"lab8c_team": ["SHIFT+T", "Lab: next counter-nanite team", "lab8c", "cn_specialize"],
	"lab8c_path": ["SHIFT+P", "Lab: next specialisation path", "lab8c", "cn_specialize"],
	"lab8c_spec": ["SHIFT+S", "Lab: specialise the team's next operator", "lab8c", "cn_specialize"],
}
const PAGE_GROUPS := ["squad7", "cn8p", "arm8b", "gar8b", "bar8c", "air8c", "aid8c", "lab8c"]   # cn8p: G7 CNMISSION8 strike-team pages; arm8b / gar8b: G7 CARDS8B building cards
const G7_SHARE := [["drone7", "drone"], ["drone7", "loadout6"],
	# fissure7 (Span fissure) sits on the engineer / repair-unit card next to their G6 actions
	["fissure7", "mines6"], ["fissure7", "rail6"], ["fissure7", "garrison6"], ["fissure7", "loadout6"],
	["fissure7", "breach6"], ["fissure7", "tow6"], ["fissure7", "bridge6"], ["fissure7", "eng_air"],
	["fissure7", "truck"], ["fissure7", "medic"], ["fissure7", "cn7"],
	["vanta7", "air"],   # G7 AIRV7: the Vanta card sits on the air card
	["so8", "cn7"], ["so8", "fissure7"], ["so8", "vanta7"], ["so8", "air"]]   # G7 SPECOPS8: the spec-ops buttons sit on the cn7 card

## Group pairs that can appear on one card together (mixed selections), so must not collide.
const SHARE := [["air", "naval"], ["drone", "truck"], ["drone", "medic"], ["drone", "eng_air"],
	["tactical", "truck"], ["tactical", "medic"], ["tactical", "eng_air"], ["truck", "medic"],
	["truck", "eng_air"], ["medic", "eng_air"], ["naval", "truck"], ["naval", "medic"],
	# G6 (UI6b): engineers / EOD / sappers / JTAC / synths mix these on one infantry card
	["mines6", "rail6"], ["mines6", "garrison6"], ["mines6", "loadout6"], ["rail6", "garrison6"],
	["rail6", "loadout6"], ["garrison6", "loadout6"], ["breach6", "mines6"], ["breach6", "rail6"],
	["breach6", "garrison6"], ["breach6", "loadout6"], ["designate6", "garrison6"], ["designate6", "loadout6"],
	["designate6", "mines6"], ["designate6", "breach6"], ["designate6", "strike6"], ["cloak6", "garrison6"],
	["cloak6", "loadout6"], ["cloak6", "breach6"], ["cloak6", "mines6"], ["cloak6", "assim6"],
	["strike6", "mines6"], ["strike6", "aerostat6"], ["designate6", "aerostat6"], ["bridge6", "mines6"],
	["bridge6", "strike6"], ["tow6", "mines6"], ["tow6", "rail6"],
	["airdrop6", "air"], ["airdrop6", "naval"], ["sub6", "air"], ["sub6", "naval"], ["seamine6", "air"],
	["seamine6", "naval"], ["airdrop6", "sub6"], ["airdrop6", "seamine6"], ["sub6", "seamine6"]]
## G6 (UI6b): group pairs that DO share a card (one unit def is in both) but cannot get unique static keys
## (11 free letters for 39 unit actions). On such a card the G6 action yields: G6Cmds gives it the first
## key of G6_FALLBACK not yet on the card (fallback_key), so the earlier G1-G5 button keeps its key.
## The Drone Team (drone / tactical modes) is foot infantry with loadouts: Garrison Z and Loadout V
## would take Strike drone Z / EMP drone V / Infiltrate Z / Stack up V.
const YIELD := [["drone", "garrison6"], ["drone", "loadout6"], ["tactical", "garrison6"], ["tactical", "loadout6"]]
## Fallback keys for a yielding G6 action: J/U/X/Z first (G3.AVOID_KEYS: no generated or data build key
## uses them), then the other free card letters.
const G6_FALLBACK := ["J", "U", "X", "Z", "K", "N", "B", "T", "Y", "C", "V"]
const UNIT_GROUPS := ["air", "drone", "tactical", "truck", "medic", "naval", "eng_air"]
const G6_UNIT_GROUPS := ["mines6", "rail6", "garrison6", "loadout6", "designate6", "breach6", "cloak6", "strike6",
	"bridge6", "aerostat6", "assim6", "tow6", "airdrop6", "sub6", "seamine6"]
const BUILDING_GROUPS := ["airfield", "hangar", "garrison_bld6", "battery6", "garage6"]
const G6_BUILDING_GROUPS := ["garrison_bld6", "battery6", "garage6"]
## G6 command icon per action (ART-G6b icons/<command>.png, through ArtCatalog.icon).
const ICONS := {"minefield": "lay_minefield", "sea_mines": "lay_sea_mines", "battery_strike": "strike",
	"loadout": "set_loadout"}


## ArtCatalog icon id for a G6 action ("" for G5 actions, which have no command icon).
static func icon_id(action: String) -> String:
	if not ACTIONS.has(action) or not (G6_UNIT_GROUPS.has(group(action)) or G6_BUILDING_GROUPS.has(group(action))):
		return ""
	return String(ICONS.get(action, ACTIONS[action][3]))

static var _user: Dictionary = {}     # action -> key (loaded from Settings)
static var _loaded := false


static func set_user_bindings(b: Dictionary) -> void:
	_user = {}
	for a in b:
		if ACTIONS.has(String(a)) or G7_ACTIONS.has(String(a)):   # G7: the G7 rows are rebindable too
			_user[String(a)] = String(b[a]).to_upper()
	_loaded = true


static func user_bindings() -> Dictionary:
	return _user.duplicate()


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var S = load("res://presentation/menu/settings.gd")
	if S != null:
		set_user_bindings(S.get_bindings())


## Current key for a G5 action ("" if unknown); FIXED actions answer their fixed key.
static func key(action: String) -> String:
	if FIXED.has(action):
		return String(FIXED[action][0])
	if GLOBAL_ACTIONS.has(action):
		return String(GLOBAL_ACTIONS[action][0])
	if G7_ACTIONS.has(action):
		_ensure()
		return String(_user.get(action, G7_ACTIONS[action][0]))
	if not ACTIONS.has(action):
		return ""
	_ensure()
	return String(_user.get(action, ACTIONS[action][0]))


static func badge(k: String) -> String:
	if k.to_upper().begins_with("SHIFT+"):   # G7: Shift chords (treat_casualty / evacuate_casualty)
		return "Sh+" + badge(k.substr(6))
	return String(BADGE.get(k.to_upper(), k))


## G7: the hotkey string for a key event as the card map stores it: "SHIFT+T" when Shift is held and that chord
## is registered in `registered` (the hud's key -> button map), else the plain key ("T"), so Shift+<letter>
## still reaches a plain-letter button when no chord owns it (the G1-G6.1 behaviour).
static func event_key(k: InputEventKey, registered: Dictionary = {}) -> String:
	var base := OS.get_keycode_string(k.keycode).to_upper()
	if k.shift_pressed and registered.has("SHIFT+" + base):
		return "SHIFT+" + base
	return base


static func label(action: String) -> String:
	if FIXED.has(action):
		return String(FIXED[action][1])
	if GLOBAL_ACTIONS.has(action):
		return String(GLOBAL_ACTIONS[action][1])
	if G7_ACTIONS.has(action):
		return String(G7_ACTIONS[action][1])
	return String(ACTIONS[action][1]) if ACTIONS.has(action) else action


static func group(action: String) -> String:
	if G7_ACTIONS.has(action):
		return String(G7_ACTIONS[action][2])
	return String(ACTIONS[action][2]) if ACTIONS.has(action) else "fixed"


## True when groups ga / gb share a card with the G6 one yielding its key (YIELD).
static func yields(ga: String, gb: String) -> bool:
	for p in YIELD:
		if (p[0] == ga and p[1] == gb) or (p[0] == gb and p[1] == ga):
			return true
	return false


## The key a yielding G6 action takes on a card whose keys are `taken` (key -> anything): the first free
## G6_FALLBACK letter, "" when none is free (the button then has no hotkey).
static func fallback_key(taken: Dictionary) -> String:
	for k in G6_FALLBACK:
		if not taken.has(k):
			return String(k)
	return ""


static func shares(ga: String, gb: String) -> bool:
	if PAGE_GROUPS.has(ga) or PAGE_GROUPS.has(gb):
		return ga == gb   # G7: a page replaces the card, so it shares with nothing else
	if ga == gb or ga == "fixed" or gb == "fixed":
		return true
	for p in G7_SHARE:
		if (p[0] == ga and p[1] == gb) or (p[0] == gb and p[1] == ga):
			return true
	if ga == "squad61" or gb == "squad61" or ga == "bearer61" or gb == "bearer61" or ga == "wound7" or gb == "wound7":
		return true   # G6.1: on every combat unit card (bearers mix with any infantry selection)
	for p in SHARE:
		if (p[0] == ga and p[1] == gb) or (p[0] == gb and p[1] == ga):
			return true
	return false


## Unit groups and building groups never share a card; the fixed G1-G4 keys only sit on unit cards.
static func _same_card_kind(ga: String, gb: String) -> bool:
	var a_b := BUILDING_GROUPS.has(ga)
	var b_b := BUILDING_GROUPS.has(gb)
	if a_b or b_b:
		return a_b and b_b and ga == gb
	return true


static func all_actions() -> Array:
	var out: Array = FIXED.keys()
	out.append_array(ACTIONS.keys())
	out.append_array(G7_ACTIONS.keys())
	out.sort()
	return out


## Every pair of actions whose keys collide on some card, or a card key that is a GLOBAL key.
## [] = clean. Each entry: "a/b: K".
static func collisions(bindings: Dictionary = {}) -> Array:
	var out: Array = []
	var acts := all_actions()
	var kof := func(a: String) -> String:
		return String(bindings.get(a, key(a))).to_upper()
	for a in acts:
		var k: String = kof.call(a)
		if k == "":
			out.append("%s: no key" % a)
		elif GLOBAL.has(k):
			out.append("%s: %s is a global key" % [a, k])
	for i in acts.size():
		for j in range(i + 1, acts.size()):
			var a: String = acts[i]
			var b: String = acts[j]
			var ga := group(a)
			var gb := group(b)
			if not _same_card_kind(ga, gb) or not shares(ga, gb):
				continue
			if kof.call(a) == kof.call(b):
				out.append("%s/%s: %s" % [a, b, kof.call(a)])
	return out


## Why `k` cannot be bound to `action` ("" = ok). Used by the settings rebinding UI.
static func rebind_error(action: String, k: String) -> String:
	if not ACTIONS.has(action) and not G7_ACTIONS.has(action):
		return "This key is fixed."
	k = k.to_upper()
	# G7: G7 actions may also take a Shift+<letter> chord (their defaults are chords: casualty and counter-nanite keys)
	var chord := G7_ACTIONS.has(action) and k.length() == 7 and k.begins_with("SHIFT+") and k[6] >= "A" and k[6] <= "Z"
	if group(action) == "squad61" or group(action) == "wound7":
		if not PUNCT_KEYS.has(k) and not (chord and group(action) == "wound7"):
			return "Use , ; / ' [ ] \\ - or =." if group(action) == "squad61" else "Use , ; / ' [ ] \\ - = or Shift+<letter>."
	elif not chord and (k.length() != 1 or k < "A" or k > "Z"):
		return "Use a letter key." if not G7_ACTIONS.has(action) else "Use a letter key or Shift+<letter>."
	var trial := _user.duplicate()
	trial[action] = k
	for c in collisions(trial):
		if String(c).begins_with(action + "/") or String(c).contains("/" + action + ":") or String(c).begins_with(action + ":"):
			return "%s is already used: %s." % [k, c]
	return ""


## F1 sheet rows for the G5 actions: [key, "Label (group)"].
static func sheet_rows() -> Array:
	var names := {"air": "aircraft", "drone": "Drone Team", "tactical": "Drone Team, tactical mode",
		"truck": "supply truck", "medic": "medic / ambulance", "naval": "ships", "eng_air": "airfield engineers",
		"airfield": "airfield selected", "hangar": "hangar selected",
		"mines6": "engineers / EOD / mine clearer", "rail6": "engineers", "garrison6": "infantry",
		"loadout6": "infantry near a barracks or Company HQ", "designate6": "JTAC", "breach6": "sappers / breacher",
		"cloak6": "Stalker Synth", "strike6": "loitering-munition truck / MLRS", "bridge6": "bridge layer",
		"aerostat6": "aerostat", "assim6": "Assimilator", "tow6": "salvage crane / dozer", "airdrop6": "airlifter",
		"sub6": "submarine", "seamine6": "mine barge", "garrison_bld6": "garrisoned building selected",
		"battery6": "strike battery selected", "garage6": "Exo-Suit Garage selected",
		"squad61": "combat units", "squad7": "formation page", "drone7": "Drone Team (flying)",
		"wound7": "infantry / medics / carriers", "cn7": "counter-nanite strike / tactical team",
		"fissure7": "engineers"}
	var out: Array = []
	var acts: Array = ACTIONS.keys() + G7_ACTIONS.keys()
	acts.sort_custom(func(a, b): return _order(a) < _order(b))
	for a in acts:
		out.append([key(a), "%s (%s)" % [label(a), names.get(group(a), group(a))]])
	return out


static func _order(a: String) -> String:
	var g := group(a)
	var all: Array = UNIT_GROUPS + G6_UNIT_GROUPS + BUILDING_GROUPS
	return "%02d_%s" % [all.find(g) if all.has(g) else 99, a]
