class_name SimWorld
extends RefCounted
## Authoritative simulation state + fixed-step tick orchestrator + command bus.
## Pure logic: no Nodes, no rendering, no global RNG. See docs/CONTRACTS.md.

const SCHEMA_VERSION := 4  # 4 = G4 (cargo, walls, mines, triggers); 2 = G2 (fuel/ammo ledger, unit tactical fields, bridge); 3 = G3b (stage/research/advancing)
const TICK_RATE := 20
const DT := 1.0 / 20.0
const EVENT_LOG_MAX := 300
const NEUTRAL := -1

const Economy = preload("res://sim/systems/economy.gd")
const Construction = preload("res://sim/systems/construction.gd")
const Production = preload("res://sim/systems/production.gd")
const Gather = preload("res://sim/systems/gather.gd")
const Movement = preload("res://sim/systems/movement.gd")
const Combat = preload("res://sim/systems/combat.gd")
const Fog = preload("res://sim/systems/fog.gd")
const Victory = preload("res://sim/systems/victory.gd")
const AiController = preload("res://sim/ai/ai_controller.gd")
const Morale = preload("res://sim/systems/morale.gd")
const Supply = preload("res://sim/systems/supply.gd")
const Repair = preload("res://sim/systems/repair.gd")
const Ops = preload("res://sim/systems/ops.gd")
const Orders = preload("res://sim/systems/orders.gd")
const Bridges = preload("res://sim/systems/bridges.gd")
const MapGen = preload("res://sim/map_gen.gd")
const Progression = preload("res://sim/systems/progression.gd")
const Tiers = preload("res://sim/systems/tiers.gd")
const SimIndex = preload("res://sim/systems/sim_index.gd")
const Fortify = preload("res://sim/systems/fortify.gd")
const Transport = preload("res://sim/systems/transport.gd")
const G4bMech = preload("res://sim/systems/g4b_mech.gd")
const Triggers = preload("res://sim/systems/triggers.gd")
const MapIO = preload("res://sim/map_io.gd")
const RenderSnap = preload("res://sim/render_snap.gd")
# G5 (CONTRACTS_G5 section 2)
const Airfield = preload("res://sim/systems/airfield.gd")
const Air = preload("res://sim/systems/air.gd")
const Naval = preload("res://sim/systems/naval.gd")
const G5Mech = preload("res://sim/systems/g5_mech.gd")
const Medical = preload("res://sim/systems/medical.gd")
const Support = preload("res://sim/systems/support.gd")
const HotState = preload("res://sim/hot_state.gd")
# G6 (CONTRACTS_G6 section 2): new systems (stubs until their owners fill them in)
const Market = preload("res://sim/systems/market.gd")
const Companies = preload("res://sim/systems/companies.gd")
const AiCommand = preload("res://sim/systems/ai_command.gd")
const Mines = preload("res://sim/systems/mines.gd")
const Fieldworks = preload("res://sim/systems/fieldworks.gd")
const Garrison = preload("res://sim/systems/garrison.gd")
const Rail = preload("res://sim/systems/rail.gd")
const Mobility = preload("res://sim/systems/mobility.gd")
const Engineering = preload("res://sim/systems/engineering.gd")  # G6: salvage crane, repair bay, breach (MECH6a)
const Sonar = preload("res://sim/systems/sonar.gd")
const Airdef = preload("res://sim/systems/airdef.gd")
const Counterdrone = preload("res://sim/systems/counterdrone.gd")
const Ciws7 = preload("res://sim/systems/ciws7.gd")  # G7 CIWS7 CR 7277 (13.9c-32): roof CIWS on the command centre
const MachineG6 = preload("res://sim/systems/machine_g6.gd")
const Strikes = preload("res://sim/systems/strikes.gd")
const Callins = preload("res://sim/systems/callins.gd")
const Exo = preload("res://sim/systems/exo.gd")
const Auras = preload("res://sim/systems/auras.gd")
const Waves = preload("res://sim/systems/waves.gd")
const Elevation = preload("res://sim/systems/elevation.gd")   # library (no tick)
const Loadouts = preload("res://sim/systems/loadouts.gd")     # library (no tick)
const G6Hooks = preload("res://sim/systems/g6_hooks.gd")      # dispatcher (CONTRACTS_G6 section 5.1)
const Commanders = preload("res://sim/ai/commanders.gd")      # player-side AI commanders (AI7-CMD)
const SquadAI = preload("res://sim/systems/squad_ai.gd")       # G6.1 squad AI (SQUAD61)
const AmmoBearer = preload("res://sim/systems/ammo_bearer.gd") # G6.1 ammo bearer (BEARER61)
const Wounds = preload("res://sim/systems/wounds.gd") # G7 hit zones + casualty care (WOUND7)
const DronePilot = preload("res://sim/systems/drone_pilot.gd") # G7 player-flown drones (DRONE7)
const Convoy = preload("res://sim/systems/convoy.gd") # G7 motorcade convoys + moving cover (SQUAD7)
const Flow71 = preload("res://sim/systems/flow71.gd") # G7.1 A3 one-click deploy, auto logistics, mission templates (FLOW71)
const Parts71 = preload("res://sim/systems/parts71.gd")  # G7.1 wave 2 DAMAGE71 B2 component damage (CR 954)
const Gore71 = preload("res://sim/systems/gore71.gd")  # G7.1 wave 2 DAMAGE71 J1/J3 wound outcomes
const Care71 = preload("res://sim/systems/care71.gd")  # G7.1 wave 2 DAMAGE71 J2/G1 triage + medics
const Turrets71 = preload("res://sim/systems/turrets71.gd")  # G7.1 wave 2 BASTION71 turrets (CR 970)
const Walls71 = preload("res://sim/systems/walls71.gd")  # G7.1 wave 2 BASTION71 wall tiers / gates / chokes
const Sensors71 = preload("res://sim/systems/sensors71.gd")  # G7.1 wave 2 BASTION71 sonic / seismic sensors
const KillZone71 = preload("res://sim/systems/killzone71.gd")  # G7.1 wave 2 FIRES71 kill zones / FPF lines (CR 978)
const Fires71 = preload("res://sim/systems/fires71.gd")  # G7.1 wave 2 FIRES71 fire missions / belts
const Conductor71 = preload("res://sim/systems/conductor71.gd")  # G7.1 wave 2 FIRES71 B6 CONDUCTOR gunship (CR seq 1748)
const Gas71 = preload("res://sim/systems/gas71.gd")  # G7.1 wave 2 CNOPS71 J10 gas (CR 1001)
const Hospital71 = preload("res://sim/systems/hospital71.gd")  # G7.1 wave 2 CNOPS71 hospital
const Infect71 = preload("res://sim/systems/infect71.gd")  # G7.1 J5 nanite wound infection
const Stim71 = preload("res://sim/systems/stim71.gd")  # G7.1 J9 combat stimulants
const Warmind71 = preload("res://sim/systems/warmind71.gd")  # G7.1 J13 AI war-mind
const Recomplex71 = preload("res://sim/systems/recomplex71.gd")  # G7.1 J12 Site Blackglass
const Conduct71 = preload("res://sim/systems/conduct71.gd")  # G7.1 J14 conduct cost
const Neural71 = preload("res://sim/systems/neural71.gd")  # G7.1 J9 neural-link pilots
const Horror71 = preload("res://sim/systems/horror71.gd")  # G7.1 J7 horror atmosphere
const Atmo71 = preload("res://sim/systems/atmo71.gd")  # G7.1 E1 end-battle atmosphere
const Weather71 = preload("res://sim/systems/weather71.gd")  # G7.1 I3 wind + fog mornings
const Tod71 = preload("res://sim/systems/tod71.gd")  # TOD71 LP day/night clock (night = 2× day)
const Night71 = preload("res://sim/systems/night71.gd")  # G7.1 I5 night / illumination
const Smoke71 = preload("res://sim/systems/smoke71.gd")  # G7.1 H12 smoke columns
const Request71 = preload("res://sim/systems/request71.gd")  # G7.1 I1 request queue
const Hive71 = preload("res://sim/systems/hive71.gd")  # G7.1 I6 hive nests/relays
const Fire71 = preload("res://sim/systems/fire71.gd")  # G7.1 I4 wildfire wind-spread
const Death71 = preload("res://sim/systems/death71.gd")  # G7.1 I7 machine deaths
const Harvest71 = preload("res://sim/systems/harvest71.gd")  # G7.1 J4 harvester swarm
const Capture71 = preload("res://sim/systems/capture71.gd")  # G7.1 H11 captured machine study
const Evolve71 = preload("res://sim/systems/evolve71.gd")  # G7.1 H11 hive evolve stages
const Hive9 = preload("res://sim/systems/hive9.gd")  # G9 HIVE9 nanite / replicate / adapt
const Count9 = preload("res://sim/systems/count9.gd")  # G9 COUNT9 thirteen Machine counters
const Combat9 = preload("res://sim/systems/combat9.gd")  # G9 COMBAT9 terrain geom + ballistics harness
const Skirm9 = preload("res://sim/systems/skirm9.gd")  # G9 SKIRM9 skirmish Tide siege roster
const CnMission71 = preload("res://sim/systems/cnmission71.gd")  # G7.1 wave 2 CNOPS71 D7 area missions (CR seq 1811)
const Ammo71 = preload("res://sim/systems/ammo71.gd")  # G7.1 wave 2 ARMY71 B3 ammo tiers (CR seq 1651; commands only, no tick slot)
const Crew71 = preload("res://sim/systems/crew71.gd")  # G7.1 wave 2 ARMY71 B3 crew-served weapons (CR seq 1863; commands only, no tick slot)
const Creep = preload("res://sim/systems/creep.gd") # G7 Machine creep + seeds (CREEP7)
const Cores = preload("res://sim/systems/cores.gd") # G7 doomsday/living cores + escalation (CREEP7)
const CounterNanite = preload("res://sim/systems/counter_nanite.gd") # G7 counter-nanite ops (CNSIM7)
const CnMission8 = preload("res://sim/systems/cn_mission8.gd")  # G7 CNMISSION8 (13.9c-44): one-click purge mission
const SpecOps8 = preload("res://sim/systems/specops8.gd")  # G7 SPECOPS8 (13.9c-44): spec-ops missions (escort, core raid, recon & mark, rescue)
const Apc7 = preload("res://sim/systems/apc7.gd") # G7 advanced APC systems (CNSIM7)
const CnFacility = preload("res://sim/systems/cn_facility.gd") # G7 Counter-Nanite facility (CNFAC7)
const WallWalk7 = preload("res://sim/systems/wallwalk7.gd") # G7 WALL7 walkable facility walls (CR 3391)
const CnOps7 = preload("res://sim/systems/cn_ops7.gd") # G7 CN operation support: overwatch drone, fire support, relief (CNOPS7)
const DroneBay7 = preload("res://sim/systems/drone_bay7.gd") # G7 DRONEBAY7 CR 5573: facility drone bay defence drone garrison (13.9c-27)
const CnProgress7 = preload("res://sim/systems/cn_progress7.gd") # G7 CN progression: named operators, team XP, bonds (CNOPS7)
const BaseState7 = preload("res://sim/systems/base_state7.gd") # G7 base secure state (CNFAC7)
const Threats7 = preload("res://sim/systems/threats7.gd") # G7 Machine threat units (THREAT7)
const LastProtocol = preload("res://sim/systems/last_protocol.gd") # G7 Last Protocol mode rules (LPMODE7)
const Research71 = preload("res://sim/systems/research71.gd")  # G7.1 H7 siege tech tree
const Fissures7 = preload("res://sim/systems/fissures7.gd")  # G7 FISSURE7: creep fissures, canyons, growths (ticked from Creep)
const Turrets7 = preload("res://sim/systems/turrets7.gd") # G7 8 Human A turrets (TURRET7 CR seq 480)
const WallTurret7 = preload("res://sim/systems/wallturret7.gd") # G7 WTUR7 unmanned facility wall turrets (CR 3636)
const Sentinels7 = preload("res://sim/systems/sentinels7.gd")  # G7 SENT7 (CR 3681)
const LpReserve7 = preload("res://sim/systems/lp_reserve7.gd")  # G7 LPRES7 (13.9c-34): Last Protocol 100-Sentinel barracks reserve
const Engineer7 = preload("res://sim/systems/engineer7.gd")  # G7 ENG7 Facility Engineer (CR 3963)
const Supply8 = preload("res://sim/systems/supply8.gd")  # G7 SUPPLY8 (13.9c-48): magazine card + airdrop retrieval op
const Cards8b = preload("res://sim/systems/cards8b.gd")  # G7 CARDS8B (13.9c-48): armory + garage building cards
const Cards8c = preload("res://sim/systems/cards8c.gd")  # G7 CARDS8C (13.9c-48): barracks / air / aid station building cards
const Cards8a = preload("res://sim/systems/cards8a.gd")  # G7 CARDS8A (13.9c-48): command centre + defences building cards
const Blast8 = preload("res://sim/systems/blast8.gd")  # G7 BLAST8 (13.9c-47): blast throw ragdoll arc + concussion comas
const FacDrive7 = preload("res://sim/systems/fac_drive7.gd")  # G7 APCMOV7 facility APC traffic (13.9c-16)
const VehDrive7 = preload("res://sim/systems/veh_drive7.gd")  # G7 PATH7 CR 6658: open-ground CN APC driver (13.9c-16a)
const Vanta7 = preload("res://sim/systems/vanta7.gd")  # G7 AIRV7 CN Vanta gunship (CR 4527)
const CommandNet = preload("res://sim/systems/command_net.gd") # G6.1 chain of command + comms (CHAIN61)
const Intel = preload("res://sim/systems/intel.gd")            # G6.1 per-side belief (CHAIN61)
const Plans = preload("res://sim/systems/plans.gd")            # G6.1 command layer (PLAN61)

## Systems run in this exact order every tick, after due commands are applied.
## G2: Repair/Ops/Orders issue movement before Movement runs; Morale/Supply/Bridges react to combat.
const SYSTEM_ORDER := [Economy, Market, Construction, Fortify, Airfield, Production, CnFacility, WallWalk7, Walls71, Companies, Progression, Gather, Repair, Plans, Ops, CommandNet, Intel, AiCommand, Orders, SquadAI, Convoy, Flow71, Mines, Fieldworks, Garrison, Rail, Mobility, Movement, FacDrive7, VehDrive7, DronePilot, Air, Naval, Sonar, Transport, Airdef, Counterdrone, Ciws7, Vanta7, Apc7, KillZone71, Combat, Turrets7, Turrets71, WallTurret7, Wounds, Parts71, Gore71, Care71, Blast8, Combat9, Gas71, Weather71, Tod71, Night71, Smoke71, Sentinels7, LpReserve7, Engineer7, Supply8, G4bMech, G5Mech, MachineG6, Creep, Cores, Threats7, Skirm9, Sensors71, Strikes, Fires71, Fire71, Conductor71, CounterNanite, CnMission8, CnMission71, SpecOps8, CnOps7, DroneBay7, Cards8a, Cards8b, Cards8c, Callins, Engineering, Exo, Medical, Hospital71, Infect71, Stim71, Neural71, Horror71, Atmo71, Request71, Hive71, Death71, Harvest71, Capture71, Hive9, Count9, Evolve71, Support, Auras, Morale, Supply, AmmoBearer, Bridges, Fog, Waves, Triggers, BaseState7, Research71, Recomplex71, Warmind71, Conduct71, LastProtocol, CnProgress7, Victory]
## G6 (ED6 CR live_mode_skips, CONTRACTS_G6 section 15 / D43): editor Live mode runs combat + AI tactics only.
## While cfg.live_mode is set these systems do not tick (Progression's EW jamming still does, it is combat),
## and these command types are rejected. The flag is absent outside Live, so no hash changes.
const LIVE_SKIPS := [Economy, Market, Construction, Production, Progression, Gather]
const LIVE_BLOCKED := ["build", "assist_build", "cancel_building", "queue_unit", "cancel_unit", "research",
	"advance_stage", "market_trade", "train_company", "train_commander", "build_line", "build_hangar",
	"upgrade_hangar", "upgrade_airfield"]


static func live_skips() -> Array:
	return ["Economy", "Market", "Construction", "Production", "Progression", "Gather"]

## command type -> handler script (must implement validate_command / apply_command).
const COMMANDS := {
	"move": Movement,
	"attack_move": Movement,
	"stop": Movement,
	"hold": Movement,
	"attack": Combat,
	"gather": Gather,
	"build": Construction,
	"assist_build": Construction,
	"cancel_building": Construction,
	"queue_unit": Production,
	"cancel_unit": Production,
	"set_rally": Production,
	"repair": Repair,
	"assign_officer": Ops,
	"set_mission": Ops,
	"cancel_mission": Ops,
	"patrol": Orders,
	"guard": Orders,
	"set_formation": Orders,
	"research": Progression,
	"advance_stage": Progression,
	# G4 (CONTRACTS_G4 section 2.3)
	"load": Transport,
	"unload": Transport,
	"unload_all": Transport,
	"build_line": Fortify,
	"set_gate_lock": Fortify,
	"lay_mine": G4bMech,
	"plant_charge": G4bMech,
	"deploy": G4bMech,
	# G5 (CONTRACTS_G5 section 4)
	"build_hangar": Airfield,
	"upgrade_hangar": Airfield,
	"upgrade_airfield": Airfield,
	"assign_engineers": Airfield,
	"sortie": Air,
	"rebase": Air,
	"land_at": Air,
	"take_off": Air,
	"air_patrol": Air,  # G7.1 AIRFIX71 A2 patrol loops
	"bombard": Naval,
	"launch_drone": G5Mech,
	"tactical": G5Mech,
	"set_auto_resupply": Support,
	"set_auto_evac": Medical,
	# G6 (CONTRACTS_G6 section 4)
	"market_trade": Market,
	"train_company": Companies,
	"train_commander": Companies,
	"form_army": Companies,
	"disband_army": Companies,
	"set_company_refill": Companies,
	"set_loadout": Exo,
	"resuit": Exo,
	"lay_minefield": Mines,
	"sweep": Mines,
	"lay_sea_mines": Naval,  # G6 (NAVAL6 CR naval6_commands): mine barges {issuer, unit_ids, rect:[x0,y0,x1,y1]}
	"line_charge": Mines,
	"garrison": Garrison,
	"ungarrison": Garrison,
	"build_rail": Rail,
	"deploy_bridge": Mobility,
	"pack_bridge": Mobility,
	"airdrop": Mobility,
	"designate": Callins,
	"aerostat": Callins,
	"strike": Strikes,
	"tow_wreck": Engineering,
	"breach": Engineering,
	"assimilate": MachineG6,
	"cloak": MachineG6,
	"submerge": Sonar,
	"set_ai_commander": AiCommand,
	"recall_ai_commander": AiCommand,
	"ally_request": AiCommand,
	# G6.1 (owner directive 2026-10-26)
	"set_stance": SquadAI,
	"set_technique": SquadAI,  # G7 SQUAD7 CR
	"lp_posture": LastProtocol,  # G7 LPMODE7 CR
	"lp_defence_ai": LastProtocol,
	"lp_blow_dam": LastProtocol,
	"lp_drop_bridge": LastProtocol,
	"lp_orbital_strike": LastProtocol,
	"lp_fire_support": LastProtocol,
	"cn_train": CnFacility,  # G7 CNFAC7 CR
	"cn_cancel_train": CnFacility,
	"fd7_go": FacDrive7, "cn_rollout": CnFacility,
	"cn_return": CnFacility,
	"cn_lab_queue": CnFacility,
	"cn_lab_upgrade": CnFacility,
	"cn_drill": CnFacility,
	"cn_evacuate": CnFacility,
	"cn_set_loadout": CounterNanite,  # G7 CNSIM7 CR
	"cn_pincer": CounterNanite,  # G7 CNSIM7-3 CR: anti-walker pincer on one order
	"t7_pry": Threats7,  # G7 THREAT7 CR: pry a leech off a vehicle
	"t7_cut": Threats7,  # G7 THREAT7 CR: cut a soldier out of a Weaver cocoon
	"cn_fire_support": CnOps7,  # G7 CNOPS7 CR: team leader calls fire support on a target the team can see
	"cn_relief": CnOps7,  # G7 CNOPS7 CR: relief convoy from the facility
	"cn_specialize": CnProgress7,  # G7 CNOPS7 CR: specialist upgrade path
	"fissure_span": Fissures7,  # G7 FISSURE7 CR: engineers span a fissure/canyon {issuer, unit_ids, cell:[x,y]}
	"cn_break_contact": CounterNanite,  # G7 CNSIM7-3 CR: formed withdrawal
	"cn_deploy": CounterNanite,
	"cn_hero_detonate": CounterNanite,
	"cn_dismount": CounterNanite,
	"cn_mount": CounterNanite,
	"cn_move": CounterNanite,
	"cn_mission": CnMission8, "cn_mission_cancel": CnMission8, "cn_mission_hold": CnMission8, "cn_extract": CnMission8,  # G7 CNMISSION8 (13.9c-44)
	"so_mission": SpecOps8, "so_cancel": SpecOps8,  # G7 SPECOPS8 (13.9c-44)
	"sup8_order": Supply8, "sup8_prio": Supply8, "sup8_mix": Supply8,  # G7 SUPPLY8 (13.9c-48)
	"cc_fire": Cards8a, "cc_withdraw": Cards8a, "cc_last_stand": Cards8a, "def_fire_mode": Cards8a, "def_priority": Cards8a, "gate_set": Cards8a, "def_repair": Cards8a,  # G7 CARDS8A (13.9c-48)
	"c8b_preset": Cards8b, "c8b_suit_build": Cards8b, "c8b_suit_rush": Cards8b, "c8b_suit_repair": Cards8b, "c8b_upgrade": Cards8b,  # G7 CARDS8B (13.9c-48)
	"c8b_veh_repair": Cards8b, "c8b_veh_upgrade": Cards8b, "c8b_convoy": Cards8b, "c8b_recall": Cards8b, "c8b_decon_force": Cards8b, "c8b_decon_skip": Cards8b,
	"c8c_rotate": Cards8c, "c8c_train": Cards8c, "c8c_standto": Cards8c, "c8c_plan": Cards8c, "c8c_cas_first": Cards8c, "c8c_evac": Cards8c,  # G7 CARDS8C (13.9c-48)
	"c8c_medics": Cards8c, "c8c_air_service": Cards8c, "c8c_air_launch": Cards8c, "c8c_air_recall": Cards8c, "c8c_air_cap": Cards8c,
	"cn_dome": Apc7,
	"cn_emp": Apc7,
	"cn_panels": Apc7,
	"fall_back": SquadAI,  # G7 SQUAD7 CR
	"suppress_area": SquadAI,  # G7 SQUAD7 CR
	"clear_building": Garrison,  # G7 SQUAD7 CR
	"regroup": SquadAI,
	# G7 (owners WOUND7 / DRONE7 / SQUAD7): stubs reject until the owner implements them.
	"treat_casualty": Wounds,
	"evacuate_casualty": Wounds,
	"vanta_loadout": Vanta7,  # G7 AIRV7 CR 4527
	"vanta_rtb": Vanta7,
	"dronebay_launch": DroneBay7, "dronebay_recall": DroneBay7, "dronebay_auto": DroneBay7,   # G7 DRONEBAY7 CR 5573
	"lpres_release": LpReserve7, "lpres_recall": LpReserve7, "lpres_auto": LpReserve7,   # G7 LPRES7 (13.9c-34) barracks reserve card
	"drone_take": DronePilot,
	"drone_steer": DronePilot,
	"drone_release": DronePilot,
	"drone_detonate": DronePilot,
	"drone_return": DronePilot,
	"convoy_form": Convoy,
	"convoy_move": Convoy,
	"convoy_disband": Convoy,
	"flow_send": Flow71,  # G7.1 FLOW71
	"flow_auto": Flow71,
	"flow_template_save": Flow71,
	"flow_template_launch": Flow71,
	"join_squad": AmmoBearer,
	"leave_squad": AmmoBearer,
	"issue_plan": Plans,
	"cancel_plan": Plans,
	"plan_signal": Plans,
	"set_ai_budget": AiCommand,
	"triage_tag": Care71,  # G7.1 wave 2 (ORCH wiring 2026-11-21): only types the handler already validates; later ones by change_request
	"give_morphine": Care71,
	"wall_tier": Walls71,
	"gate_reinforce": Walls71,
	"choke_seal": Walls71,
	"lift_use": Walls71,
	"berm_build": Walls71,  # G7.1 BASTION71 G2 dozer berm line (LP)
	"doze_clear": Walls71,  # G7.1 BASTION71 G2 dozer clears wrecks / bodies (LP)
	"turret_revive": Turrets71,  # BASTION71 CR seq 1644
	"ammo_tier": Ammo71,  # ARMY71 CR seq 1651
	"research71_start": Research71,  # G7.1 H7 siege tech
	"stim71_dose": Stim71,  # G7.1 J9 stimulants
	"neural71_link": Neural71,  # G7.1 J9 neural-link
	"night71_illuminate": Night71,  # G7.1 I5 illumination
	"capture71_cage": Capture71,  # G7.1 H11 capture study
	"count9_cut_relay": Count9, "count9_emp": Count9, "count9_deny": Count9,
	"count9_purge": Count9, "count9_virus": Count9, "count9_decap": Count9,
	"count9_starve": Count9, "count9_reverse": Count9, "count9_reverse_cage": Count9,
	"count9_firebreak": Count9, "count9_coalition": Count9, "count9_dead_zone": Count9,
	"count9_hunters": Count9, "count9_reprogram": Count9,  # Pre-G10: thirteen production counter paths
	"request71_reply": Request71,  # G7.1 I1 request queue
	"warmind71_reply": Warmind71,  # G7.1 J13 war-mind ask
	"recomplex71_capture": Recomplex71,  # G7.1 J12 Site Blackglass
	"recomplex71_purge": Recomplex71,
	"recomplex71_overrun": Recomplex71,
	"crew_rate": Crew71,  # ARMY71 CR seq 1863
	"crew_top": Crew71,
	"fire_mission": Fires71,
	"fpf_fire": Fires71,
	"belt_lay": Fires71,
	"belt_ignite": Fires71,
	"fo_call": Fires71,
	"conductor_orbit": Conductor71,  # FIRES71 CR seq 1748
	"conductor_home": Conductor71,
	"conductor_kamikaze": Conductor71,
	"kz_paint": KillZone71,
	"kz_clear": KillZone71,
	"fpf_paint": KillZone71,
	"hosp_quarantine": Hospital71,
	"hosp_medevac": Hospital71,
	"fac_upgrade": CnFacility,  # G7.1 CNOPS71 H8 facility upgrades (CR seq 3459)
	"gas_release": Gas71,
	"mask_on": Gas71,
	"cn_search": CnMission71,  # CNOPS71 CR seq 1811
	"cn_abort": CnMission71,
	"cn_roe": CnMission71,
}

## Direct orders that detach a unit from officer mission control (CONTRACTS_G2 section 4).
const DIRECT_ORDERS := ["move", "attack_move", "attack", "stop", "hold", "patrol", "guard", "fall_back", "suppress_area", "clear_building", "flow_send", "flow_template_launch"]  # G7: + SQUAD7 orders; G7.1: + FLOW71

# ---------------------------------------------------------------- state
var tick: int = 0
var seed_value: int = 0
var rng: SimRng = SimRng.new(1)
var next_id: int = 1
var next_cmd_id: int = 1
var map: Dictionary = {}          # see MapGen
var factions: Dictionary = {}     # fid:int -> faction dict
var entities: Dictionary = {}     # id:int -> entity dict
var pending: Array = []           # command envelopes awaiting their tick
var cfg: Dictionary = {}          # match configuration (validated)
var match_state: Dictionary = {"ended": false, "winner": NEUTRAL, "reason": "", "end_tick": -1}
var fog: Dictionary = {}          # fid -> {"visible": PackedByteArray, "explored": PackedByteArray}
var memory: Dictionary = {}       # fid -> {eid: {"def","kind","owner","pos","tick"}} last-seen enemy intel
var ai_state: Dictionary = {}     # fid -> AI controller state (serializable)
var sys_state: Dictionary = {}    # system_name -> serializable dict for any extra system-owned state

# ---------------------------------------------------------------- per-tick (not serialized)
var events: Array = []            # events emitted during the current tick
var event_log: Array = []         # rolling recent events (debug/UI)
# ---------------------------------------------------------------- runtime caches (never serialized; rebuilt)
var nav: Dictionary = {}          # owned by Movement (rebuild_nav)
var cache: Dictionary = {}        # free-form per-system caches (spatial hash etc.)
var native_enabled: bool = true   # G3b (N1-core): false forces GDScript movement/nav fallbacks; runtime only, not saved
var tiers_enabled: bool = true    # G3b (PERF4): false = every unit FULL tier; runtime only, not saved
var render_snap: Dictionary = {}  # G4 THREAD: latest render snapshot (runtime, never saved)
var snap_request: Array = []      # G4 THREAD: ids whose full dicts go into render_snap.detail
var snap_enabled: bool = false    # G4 THREAD: build render_snap at the end of step()
# >>> G5 HOT (owner CORE10K, CONTRACTS_G5 section 1): packed hot-state runtime fields go here.
var hot = null   # G5 HOT: HotState instance (sim/hot_state.gd): packed per-id hot arrays; runtime only, never saved
# <<< G5 HOT


# ================================================================ construction
## Validates a match config. Returns "" if OK, else a human-readable reason.
static func validate_config(c: Dictionary) -> String:
	Content.load_all()
	var rules := Content.rules()
	var sides: Array = c.get("sides", [])
	if sides.size() < 2:
		return "A match needs at least 2 sides."
	# G7 (owner): a map flagged skirmish:false (e.g. the Last Protocol map) only starts in its own mode.
	var g7_mdef: Dictionary = MapGen.defs().get(String(c.get("map", "")), {})
	if not bool(g7_mdef.get("skirmish", true)) and String(c.get("mode", "")) != String(g7_mdef.get("mode", "")) and not bool(c.get("dev_map", false)):
		return "This map is only available in its own game mode."
	if c.has("map_file"):
		# G4 (MAPIO CR): a file map limits sides by its own player starts
		var fr: Dictionary = MapIO.read(String(c.map_file))
		if fr.has("error"):
			return "Map file: %s" % fr.error
		var fmax := mini(int(rules.get("max_sides", 4)), (fr.map.get("spawns", []) as Array).size())
		if sides.size() > fmax:
			return "%s supports at most %d sides." % [String(fr.map.get("name", "This map")), fmax]
	else:
		var map_id := String(c.get("map", "river_crossing_s"))
		if not MapGen.has_map(map_id):
			return "Unknown map '%s'." % map_id
		var mdef: Dictionary = MapGen.defs().get(map_id, {})
		var max_sides := mini(int(rules.get("max_sides", 4)), int(mdef.get("max_sides", 4)))
		if sides.size() > max_sides:
			return "%s supports at most %d sides." % [String(mdef.get("name", map_id)), max_sides]
	var teams := {}
	for s in sides:
		if Content.faction(String(s.get("faction", ""))).is_empty():
			return "Unknown faction '%s'." % s.get("faction", "")
		teams[int(s.get("team", sides.find(s)))] = true
		var stage := int(s.get("stage", 8))
		if stage < 1 or stage > 13:
			return "Stage %d is not a valid stage ID (1-13)." % stage
		var playable := false
		for st in Content.stages():
			if int(st.id) == stage and st.get("playable_now", false):
				playable = true
		if not playable:
			return "Stage %d is not playable in this slice (Stages 7-9 only)." % stage
		if int(s.get("credits", 0)) < 0:
			return "Starting credits cannot be negative."
	if c.has("start_stock") and (int(c.start_stock) < 0 or int(c.start_stock) > 50000):
		return "Starting resources must be 0-50000."
	if teams.size() < 2:
		return "All sides are on the same team: there is nobody to fight."
	if not rules.victory_types.has(c.get("victory", "")):
		return "Unsupported victory condition '%s'." % c.get("victory", "")
	var vr := Victory.validate_rules(c)
	if vr != "":
		return vr
	if not rules.get("economy_profiles", {}).has(String(c.get("economy", "standard"))):
		return "Unknown economy profile '%s'." % c.get("economy", "")
	if not rules.get("advancement", {}).get("rules", {}).has(String(c.get("advancement", "standard"))):
		return "Unknown advancement rules '%s'." % c.get("advancement", "")
	if not rules.ai_difficulties.has(c.get("ai_difficulty", "normal")):
		return "Unknown AI difficulty '%s'." % c.get("ai_difficulty", "")
	return ""


## Default 2-side config: player (fid 0, human_a) vs AI (fid 1, human_b).
static func default_config() -> Dictionary:
	Content.load_all()
	var d: Dictionary = Content.rules().defaults
	return {
		"seed": int(d.seed),
		"map": "river_crossing_s",
		"victory": String(d.victory),
		"ai_difficulty": String(d.ai_difficulty),
		"economy": "standard",
		"advancement": "standard",
		"sides": [
			{"faction": "human_a", "stage": 8, "credits": int(d.starting_credits), "ai": false, "name": "You", "team": 0},
			{"faction": "human_a", "stage": 8, "credits": int(d.starting_credits), "ai": true, "name": "Modern AI", "team": 1},
		],
	}
	# NOTE: default_config stays Human A vs Human A (tests/autostart rely on it); the skirmish menu
	# builds its own multi-faction configs.


## Creates a fully initialized match. Returns null and push_error on invalid config.
static func new_match(c: Dictionary) -> SimWorld:
	Content.load_all()
	var reason := validate_config(c)
	if reason != "":
		push_error("SimWorld.new_match: " + reason)
		return null
	var w := SimWorld.new()
	w.cfg = c.duplicate(true)
	w.seed_value = int(c.get("seed", 1))
	w.rng = SimRng.new(w.seed_value)
	if c.has("map_file"):
		# G4 (CONTRACTS_G4 section 5): map from a .rtsmap file (MAPIO owns MapIO.load_map / place_entities)
		var merr := MapIO.load_map(w, c)
		if merr != "":
			push_error("SimWorld.new_match: " + merr)
			return null
	else:
		w.map = MapGen.generate(w.seed_value, String(c.get("map", "river_crossing_s")))
	var rules := Content.rules()
	var colors: Array = rules.team_colors
	for i in c.sides.size():
		var s: Dictionary = c.sides[i]
		var spawns: Array = w.map.spawns
		w.factions[i] = {
			"team": int(s.get("team", i)),
			"id": i,
			"name": String(s.get("name", "Side %d" % i)),
			"faction_def": String(s.faction),
			"color": String(s.get("color", colors[i % colors.size()])),  # G3a: menu colour wins
			"is_ai": bool(s.get("ai", false)),
			"stage": int(s.get("stage", 8)),
			"credits": int(s.get("credits", 0)),
			"stock": _start_stock(c, rules),
			"power_prod": 0,
			"power_use": 0,
			"pop": 0,
			"pop_cap": 0,
			"alive": true,
			"spawn": MapGen.spawn_for(w.map, i, c.sides.size()),  # MAP4: spawn_sets (G3b section 4)
			"journal": [],   # ledger audit: {tick, credits, salvage, ore, cause}
			"stats": {"trained": 0, "built": 0, "lost": 0, "killed": 0,
				"ore_refined": 0, "power_ok_ticks": 0, "line_trained": 0, "officers_trained": 0},
			# G3b progression (CONTRACTS_G3b section 2)
			"research": {"done": [], "active": "", "progress": 0.0, "facility": -1},
			"advancing": {"to": 0, "ticks_left": 0},
		}
	for r in w.map.resources:
		w.spawn_resource(String(r.res), int(r.amount), Vector2(r.cell) + Vector2(0.5, 0.5))
	for fid in w.factions:
		if bool(w.map.get("start_packages", true)):
			w._place_start_package(fid)
	if c.has("map_file"):
		MapIO.place_entities(w, c)   # G4: pre-placed units/buildings, tags, regions, triggers
	w._spawn_bridge()
	Movement.rebuild_nav(w)
	Fog.init_faction_fog(w)
	for fid in w.factions:
		if w.factions[fid].is_ai:
			w.ai_state[fid] = AiController.new_state(w, fid)
	Economy.tick(w)  # establish power/pop before first frame
	Fog.tick(w)
	return w


func _place_start_package(fid: int) -> void:
	var fdef := String(factions[fid].faction_def)
	var fd := Content.faction(fdef)
	var pkg := {"units": fd.get("start_units", Content.rules().start_package.units)}
	var spawn: Vector2i = factions[fid].spawn
	var hq_def := Content.role(fdef, "hq")
	var size := int(Content.building(hq_def).size)
	var origin := spawn - Vector2i(size / 2, size / 2)
	var hq_id := spawn_building(hq_def, fid, origin, true)
	var i := 0
	for u in pkg.units:
		var ang := float(i) / float(pkg.units.size()) * TAU
		var p := Vector2(spawn) + Vector2(0.5, 0.5) + Vector2(cos(ang), sin(ang)) * 3.0
		spawn_unit(String(u), fid, p)
		i += 1


# ================================================================ tick
func step() -> void:
	if match_state.ended:
		events = []  # never re-broadcast the final tick's events after the match ends
		return
	tick += 1
	events = []
	_apply_due_commands()
	var live := bool(cfg.get("live_mode", false))
	for sys in SYSTEM_ORDER:
		if live and LIVE_SKIPS.has(sys):
			if sys == Progression:
				Progression.Status.ew_tick(self)  # EW jamming is combat: keep it in Live
			continue
		sys.tick(self)
	Ops.prune(self)  # end-of-tick: groups never reference units that died this tick
	for fid in ai_state:
		if factions[fid].alive:
			AiController.think(self, fid)
	# G6 (CONTRACTS_G6 section 2.5): player-side AI commanders run for non-AI sides (stub: no-op)
	var g6_fids: Array = factions.keys()
	g6_fids.sort()
	for fid in g6_fids:
		if factions[fid].alive and not ai_state.has(fid):
			Commanders.think_player(self, fid)
	for ev in events:
		event_log.append(ev)
	if event_log.size() > EVENT_LOG_MAX:
		event_log = event_log.slice(event_log.size() - EVENT_LOG_MAX)
	if snap_enabled:
		HotState.flush(self)     # G5 (CORE10K CR): flush before the render snapshot
		RenderSnap.build(self)   # G4 THREAD: built on the sim thread, read by the renderer/HUD


## G3b (PERF4): fidelity tier counts {full, reduced} for perf reports.
func tier_counts() -> Dictionary:
	return Tiers.counts(self)


func run_ticks(n: int) -> void:
	for i in n:
		step()
		if match_state.ended:
			return


# ================================================================ commands
## Submit a command envelope. It is validated and applied at its authoritative tick
## (default: next tick). Returns {"ok": bool, "id": int, "reason": String}.
## Envelope: {"type": String, "issuer": fid, ...params}. See docs/CONTRACTS.md.
func submit(cmd: Dictionary) -> Dictionary:
	var c := cmd.duplicate(true)
	if not COMMANDS.has(c.get("type", "")):
		return {"ok": false, "id": -1, "reason": "Unknown command type '%s'." % c.get("type", "")}
	if not factions.has(int(c.get("issuer", NEUTRAL))):
		return {"ok": false, "id": -1, "reason": "Unknown issuer."}
	c.issuer = int(c.issuer)
	c.id = next_cmd_id
	next_cmd_id += 1
	c.tick = maxi(int(c.get("tick", tick + 1)), tick + 1)
	pending.append(c)
	return {"ok": true, "id": c.id, "reason": ""}


## Dry-run validation against current state (for UI feedback). Does not mutate.
func preview_command(cmd: Dictionary) -> String:
	var c := cmd.duplicate(true)
	if not COMMANDS.has(c.get("type", "")):
		return "Unknown command type."
	var r := _common_validate(c)
	if r != "":
		return r
	return COMMANDS[c.type].validate_command(self, c)


func _apply_due_commands() -> void:
	if pending.is_empty():
		return
	var due := []
	var later := []
	for c in pending:
		if int(c.tick) <= tick:
			due.append(c)
		else:
			later.append(c)
	pending = later
	due.sort_custom(func(a, b): return int(a.id) < int(b.id))
	for c in due:
		var reason := _common_validate(c)
		if reason == "":
			reason = COMMANDS[c.type].validate_command(self, c)
		if reason != "":
			emit("CommandRejected", {"command_id": c.id, "type": c.type, "issuer": c.issuer, "reason": reason})
			continue
		COMMANDS[c.type].apply_command(self, c)
		CnMission8.on_applied(self, c)  # G7 CNMISSION8: a fresh player order to a team on a purge mission takes over
		SpecOps8.on_applied(self, c)  # G7 SPECOPS8: same for a spec-ops squad on a mission
		AiCommand.on_applied(self, c)  # G6 (AI7-CMD CR 743): stamps e.player_order_tick; no-op unless the side used AI commanders
		if DIRECT_ORDERS.has(String(c.type)):
			Ops.on_direct_order(self, c)
			SquadAI.on_direct_order(self, c)  # G6.1 (SQUAD61 CR seq 25)
		elif String(c.type) == "set_formation":
			SquadAI.on_direct_order(self, c)
		emit("CommandApplied", {"command_id": c.id, "type": c.type, "cmd_type": String(c.type), "issuer": c.issuer})  # G6.1: cmd_type survives the event envelope (INTEG61 CR seq 406, radio acks)


## Ownership/liveness checks shared by every command. Filters unit_ids in place.
func _common_validate(c: Dictionary) -> String:
	var fid := int(c.get("issuer", NEUTRAL))
	if not factions.has(fid) or not factions[fid].alive:
		return "Issuer is not an active side."
	if match_state.ended:
		return "Match has ended."
	if bool(cfg.get("live_mode", false)) and LIVE_BLOCKED.has(String(c.get("type", ""))):
		return "Not available in Live mode."
	if c.has("unit_ids"):
		var ok_ids := []
		for raw in c.unit_ids:
			var id := int(raw)
			var e = entities.get(id)
			if e != null and e.kind == "unit" and int(e.owner) == fid:
				ok_ids.append(id)
		c.unit_ids = ok_ids
		if ok_ids.is_empty():
			return "No valid units selected."
	if c.has("building_id"):
		var b = entities.get(int(c.building_id))
		# G6 (NAVAL6 CR naval6_carrier_building_id): a carrier registered as a mobile field is a valid
		# building_id for `rebase` only; every other command still needs a real building.
		var mobile_ok: bool = b != null and b.kind == "unit" and String(c.get("type", "")) == "rebase" 			and Airfield.is_mobile(self, int(c.building_id))
		if b == null or (b.kind != "building" and not mobile_ok) or int(b.owner) != fid:
			return "Not your building."
		c.building_id = int(c.building_id)
	return ""


# ================================================================ events
func emit(type: String, data: Dictionary = {}) -> void:
	var ev := data.duplicate()
	ev.type = type
	ev.tick = tick
	events.append(ev)


# ================================================================ ledger (single source of truth for money/materials)
const LEDGER_KEYS := ["credits", "salvage", "ore", "fuel", "ammo"]

## Returns "" if faction can pay cost, else a reason like "Need 120 more salvage".
func can_afford(fid: int, cost: Dictionary) -> String:
	var f: Dictionary = factions[fid]
	for k in LEDGER_KEYS:
		var need := int(cost.get(k, 0))
		var have := _balance(f, k)
		if need > have:
			return "Need %d more %s." % [need - have, k]
	return ""


func _balance(f: Dictionary, k: String) -> int:
	return int(f.credits) if k == "credits" else int(f.stock.get(k, 0))


## Atomic: deducts the whole cost or nothing. Returns true on success.
func spend(fid: int, cost: Dictionary, cause: String) -> bool:
	if can_afford(fid, cost) != "":
		return false
	var delta := {}
	for k in LEDGER_KEYS:
		var amt := int(cost.get(k, 0))
		if amt != 0:
			delta[k] = -amt
	_apply_delta(fid, delta, cause)
	return true


## Adds resources (refunds, deliveries, stipend). Amounts must be >= 0.
func credit(fid: int, amounts: Dictionary, cause: String) -> void:
	var delta := {}
	for k in LEDGER_KEYS:
		var amt := int(amounts.get(k, 0))
		assert(amt >= 0, "credit() amounts must be non-negative")
		if amt != 0:
			delta[k] = amt
	_apply_delta(fid, delta, cause)


func _apply_delta(fid: int, delta: Dictionary, cause: String) -> void:
	if delta.is_empty():
		return
	var f: Dictionary = factions[fid]
	for k in delta:
		if k == "credits":
			f.credits = int(f.credits) + int(delta[k])
		else:
			f.stock[k] = int(f.stock.get(k, 0)) + int(delta[k])
	var entry := {"tick": tick, "cause": cause}
	entry.merge(delta)
	f.journal.append(entry)
	emit("LedgerChanged", {"faction": fid, "delta": delta, "cause": cause})


# ================================================================ entities
func spawn_unit(def_id: String, owner: int, pos: Vector2) -> int:
	var d := Content.unit(def_id)
	assert(not d.is_empty(), "unknown unit def " + def_id)
	var id := _new_id()
	entities[id] = {
		"id": id, "kind": "unit", "def": def_id, "owner": owner,
		"pos": pos, "hp": float(d.hp), "max_hp": float(d.hp),
		"order": {"type": "idle"},  # see CONTRACTS: idle|move|attack_move|attack|gather|build|hold
		"path": [], "path_i": 0,
		"target": -1, "cooldown": 0.0, "facing": _spawn_facing(owner),
		"carry": {"res": "", "amt": 0},
		"squad": -1, "moving": false, "firing": 0,
	}
	# G2 tactical fields (CONTRACTS_G2): supply, morale/suppression, vehicle components
	var e: Dictionary = entities[id]
	if d.has("ammo_max"):
		e.ammo = int(d.ammo_max)
	if d.has("fuel_max"):
		e.fuel = float(d.fuel_max)
	if d.has("components"):
		e.comp = (d.components as Dictionary).duplicate()
	if d.has("morale"):
		e.morale = float(d.morale)
		e.supp = 0.0
		e.pinned = false
		e.broken = false
	emit("EntitySpawned", {"id": id, "kind": "unit", "def": def_id, "owner": owner, "pos": pos})
	return id


## origin = top-left cell of the square footprint. complete=true for start packages.
## G7 (REGRESS7-5, ORCH ruling on need seq 2223): a new unit faces its owner's front (from the owner's start
## toward the map centre, as AiUtil.front_dir) instead of +x, so starting / scripted units watch the front
## (Senses7 view cones). Neutral or start-less owners, or an empty map: 0 as before.
func _spawn_facing(owner: int) -> float:
	var f = factions.get(owner)
	if typeof(f) != TYPE_DICTIONARY or not (f as Dictionary).has("spawn") or map.is_empty():
		return 0.0
	var sp = f.spawn
	if typeof(sp) != TYPE_VECTOR2I and typeof(sp) != TYPE_VECTOR2:
		return 0.0
	var d := Vector2(float(map.get("w", 0)), float(map.get("h", 0))) * 0.5 - (Vector2(sp) + Vector2(0.5, 0.5))
	if d.length() <= 0.01:
		d = Vector2(1, 1)
	return snappedf(d.angle(), 1.0 / 1024.0)   # the saved-float quantum (Movement.Q)


func spawn_building(def_id: String, owner: int, origin: Vector2i, complete: bool) -> int:
	var d := Content.building(def_id)
	assert(not d.is_empty(), "unknown building def " + def_id)
	var size := int(d.size)
	var id := _new_id()
	entities[id] = {
		"id": id, "kind": "building", "def": def_id, "owner": owner,
		"cell": origin, "size": size,
		"pos": Vector2(origin) + Vector2(size, size) * 0.5,
		"hp": float(d.hp) if complete else float(d.hp) * 0.1, "max_hp": float(d.hp),
		"built": complete, "progress": 1.0 if complete else 0.0,  # progress 0..1
		"queue": [],   # [{"item": prod_id, "progress": 0..1, "paid": cost dict}]
		"rally": Vector2(origin) + Vector2(size * 0.5, size + 1.0),
		"target": -1, "cooldown": 0.0, "status": "",
	}
	Movement.on_footprint_changed(self, origin, size, true)
	emit("EntitySpawned", {"id": id, "kind": "building", "def": def_id, "owner": owner, "pos": entities[id].pos})
	return id


## The neutral river bridges (MAP4, CONTRACTS_G3b section 4): one attackable structure per entry
## of map.bridges (older maps/saves: map.bridge_cells as a single bridge). The hold bridge
## (map.hold_bridge, default 0) spawns first, so Victory.bridge_entity() finds it.
func _spawn_bridge() -> void:
	var list: Array = map.get("bridges", [])
	if list.is_empty():
		var cells0: Array = map.get("bridge_cells", [])
		if cells0.is_empty():
			return
		list = [{"id": 0, "cells": cells0}]
	var hold := clampi(int(map.get("hold_bridge", 0)), 0, list.size() - 1)
	var order := [hold]
	for i in list.size():
		if i != hold:
			order.append(i)
	var d := Content.building("bridge_span")
	for i in order:
		var b: Dictionary = list[i]
		var cells: Array = b.get("cells", [])
		if cells.is_empty():
			continue
		var sum := Vector2.ZERO
		for c in cells:
			sum += Vector2(c) + Vector2(0.5, 0.5)
		var id := _new_id()
		entities[id] = {"id": id, "kind": "structure", "def": "bridge_span", "owner": NEUTRAL,
			"pos": sum / float(cells.size()), "cells": cells.duplicate(), "state": "intact",
			"hp": float(d.get("hp", 2500)), "max_hp": float(d.get("hp", 2500)), "bridge_index": int(i)}
		b["state"] = "intact"
	map.bridge_state = "intact"


func spawn_resource(res: String, amount: int, pos: Vector2) -> int:
	var id := _new_id()
	entities[id] = {"id": id, "kind": "resource", "def": res, "owner": NEUTRAL, "pos": pos,
		"hp": 1.0, "max_hp": 1.0, "res": res, "amount": amount}
	return id


## Removes an entity. Vehicles and buildings leave persistent wrecks.
## Neutral structures (the bridge) are not erased: Bridges turns them into ruins.
func destroy(id: int, cause: String, killer_owner: int = NEUTRAL) -> void:
	var e = entities.get(id)
	if e == null:
		return
	if e.kind == "structure":
		Bridges.on_destroyed(self, e, killer_owner)
		return
	entities.erase(id)
	emit("EntityDestroyed", {"id": id, "kind": e.kind, "def": e.def, "owner": e.owner,
		"pos": e.pos, "cause": cause, "killer_owner": killer_owner, "squad": int(e.get("squad", -1))})
	# G7.1 I7: machine death effects must run even when destroy is out-of-band (step clears events).
	Death71.on_destroyed(self, e)
	if e.kind == "building":
		Movement.on_footprint_changed(self, e.cell, int(e.size), false)
		_spawn_wreck(e)
	elif e.kind == "unit":
		if Content.unit(e.def).get("leaves_wreck", false):
			_spawn_wreck(e)
		if factions.has(int(e.owner)):
			factions[e.owner].stats.lost += 1
	if killer_owner != NEUTRAL and factions.has(killer_owner) and e.kind != "resource":
		factions[killer_owner].stats.killed += 1


func _spawn_wreck(e: Dictionary) -> void:
	var id := _new_id()
	entities[id] = {"id": id, "kind": "wreck", "def": e.def, "owner": NEUTRAL, "pos": e.pos,
		"hp": 1.0, "max_hp": 1.0, "from_owner": e.owner, "size": int(e.get("size", 1)),
		"facing": float(e.get("facing", 0.0)), "tick": tick}
	_spawn_scrap(e)


## G2: wrecks leave a harvestable salvage pile (rules.wreck_salvage) so long games don't starve.
## Ordinary neutral `resource` entity: gathering, fog-limited AI knowledge and rendering all apply.
func _spawn_scrap(e: Dictionary) -> void:
	var ws: Dictionary = Content.rules().get("wreck_salvage", {})
	if ws.is_empty():
		return
	var amount := 0
	if e.kind == "unit":
		amount = int(floor(float(Content.production(e.def).get("cost", {}).get("salvage", 0)) * float(ws.get("vehicle_frac", 0.0))))
	elif e.kind == "building":
		if not bool(e.get("built", false)):
			return  # foundations/cancelled sites leave no scrap (no refund+scrap exploit)
		var d := Content.building(e.def)
		if bool(d.get("is_hq", false)):
			amount = int(ws.get("hq_salvage", 0))
		else:
			amount = int(floor(float(d.get("cost", {}).get("salvage", 0)) * float(ws.get("building_frac", 0.0))))
	if amount <= 0:
		return
	var p: Vector2 = e.pos
	var c := cell_of(p + Vector2(0.7, 0.4))
	if not in_bounds(c) or not Terrain.passable(terrain_at(c), "foot"):
		c = cell_of(p)
	spawn_resource("salvage", amount, Vector2(c) + Vector2(0.5, 0.5))


func _new_id() -> int:
	var id := next_id
	next_id += 1
	return id


# ================================================================ queries
func get_e(id: int):
	return entities.get(id)


## G3a: sides on the same team are allies.
func is_enemy(a: int, b: int) -> bool:
	if a == b or a == NEUTRAL or b == NEUTRAL:
		return false
	if factions.has(a) and factions.has(b):
		return int(factions[a].get("team", a)) != int(factions[b].get("team", b))
	return true


func is_ally(a: int, b: int) -> bool:
	return a != NEUTRAL and b != NEUTRAL and not is_enemy(a, b)


## Economy profile multiplier for this match (cfg.economy; rules.economy_profiles).
func econ(key: String) -> float:
	return Content.econ(String(cfg.get("economy", "standard")), key)


func units_of(fid: int) -> Array:
	# G3b (PERF5 CR): shared per-tick index instead of a full entity scan; same members, ascending id.
	var out := []
	for e in SimIndex.of(self, "unit"):
		if int(e.owner) == fid and entities.has(int(e.id)):
			out.append(e)
	return out


func buildings_of(fid: int, def_id: String = "") -> Array:
	var out := []
	for e in SimIndex.of(self, "building"):
		if int(e.owner) == fid and (def_id == "" or e.def == def_id) and entities.has(int(e.id)):
			out.append(e)
	return out


func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < int(map.w) and cell.y < int(map.h)


func terrain_at(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return Terrain.RIDGE
	return map.terrain[cell.y * int(map.w) + cell.x]


## Fog-respecting visibility: may faction fid currently see this world position?
func is_visible(fid: int, pos: Vector2) -> bool:
	return Fog.is_visible(self, fid, pos)


## Entities of other sides that fid can currently see (the ONLY legal enemy query for AI).
func visible_enemies(fid: int) -> Array:
	return Fog.visible_enemies(self, fid)


# ================================================================ persistence
func to_dict() -> Dictionary:
	HotState.flush(self)  # G5 (CORE10K CR): packed hot state -> dicts before hash/save
	return {
		"schema_version": SCHEMA_VERSION,
		"tick": tick, "seed_value": seed_value, "rng_state": rng.state,
		"next_id": next_id, "next_cmd_id": next_cmd_id,
		"map": map, "factions": factions, "entities": entities, "pending": pending,
		"cfg": cfg, "match_state": match_state, "fog": fog, "memory": memory,
		"ai_state": ai_state, "sys_state": sys_state,
	}


static func from_dict(d: Dictionary) -> SimWorld:
	Content.load_all()
	if int(d.get("schema_version", -1)) != SCHEMA_VERSION:
		push_error("SimWorld.from_dict: unsupported schema_version %s" % d.get("schema_version"))
		return null
	var w := SimWorld.new()
	w.tick = int(d.tick)
	w.seed_value = int(d.seed_value)
	w.rng = SimRng.new(1)
	w.rng.state = int(d.rng_state)
	w.next_id = int(d.next_id)
	w.next_cmd_id = int(d.next_cmd_id)
	w.map = d.map
	w.factions = d.factions
	w.entities = d.entities
	w.pending = d.pending
	w.cfg = d.cfg
	w.match_state = d.match_state
	w.fog = d.fog
	w.memory = d.memory
	w.ai_state = d.ai_state
	w.sys_state = d.sys_state
	Movement.rebuild_nav(w)
	return w


## Stable hash of the full authoritative state (determinism / save round-trip tests).
## Uses var_to_bytes (exact doubles). var_to_str is lossy for 64-bit floats (found by F-infra).
func state_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(to_dict()))
	return ctx.finish().hex_encode()


## Starting stock of every side: the rules start package, or cfg.start_stock (0-50000, owner 2026-10-26: "start a
## match with up to 50k of all the different resources") for salvage, ore, fuel and ammo alike.
static func _start_stock(c: Dictionary, rules: Dictionary) -> Dictionary:
	if c.has("start_stock"):
		var v := clampi(int(c.start_stock), 0, 50000)
		return {"salvage": v, "ore": v, "fuel": v, "ammo": v}
	var sp: Dictionary = rules.start_package.stock
	return {"salvage": int(sp.salvage), "ore": int(sp.ore), "fuel": int(sp.get("fuel", 0)), "ammo": int(sp.get("ammo", 0))}
