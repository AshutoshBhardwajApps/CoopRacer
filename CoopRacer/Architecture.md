🏎️ CoopRacer – Architecture Overview

This document describes the full architecture of CoopRacer, covering SwiftUI structure, game logic, SpriteKit responsibilities, Ads, Audio, and extensibility.
Last updated: 2025-11-22.

⸻

1. HIGH-LEVEL STRUCTURE

CoopRacer is a SwiftUI + SpriteKit hybrid game with two main modes:
	•	Two-Player (Versus) — classic split-screen competitive race
	•	Single Player (Solo) — vertical-scrolling endless dodge runner with dynamic obstacles

Both modes use:
	•	GameCoordinator → Scorekeeping, round state, finish detection
	•	GameScene → Rendering, collisions, movement, obstacles, world simulation

SwiftUI manages UI layers (controls, overlays, sheets) while SpriteKit handles gameplay.

⸻

2. SWIFTUI LAYER

2.1 HomeView
	•	Entry screen
	•	Starts background music if enabled
	•	Buttons:
	•	“Single Player” → presents SoloGameView
	•	“Two Player” → presents ContentView
	•	“Settings” / “High Scores”
	•	Uses the global AdPresenter (hidden UIViewController) for ad presentation

⸻

2.2 ContentView (Two Player)
	•	Split-screen SpriteKit view (leftScene + rightScene)
	•	Uses PlayerControls and PlayerControlsMirrored
	•	Countdown → game start
	•	ResultsSheet on race end
	•	Shows interstitial ads between rounds
	•	Observes:
	•	.adWillPresent
	•	.adDidDismiss
	•	Pauses game on backgrounding
	•	Manages scene recreation on geometry size changes

⸻

2.3 SoloGameView (Single Player)
	•	Similar structure to ContentView, but:
	•	One SpriteKit scene only
	•	Uses solo lane width
	•	Dynamic forest (tree canopies) along edges
	•	Animated obstacle types (squirrel, tumbleweed)
	•	Solo high-score tracking
	•	Interstitial ads between runs

⸻

3. COORDINATION & STATE

3.1 GameCoordinator

Responsible for:
	•	Race start countdown
	•	roundActive state
	•	raceStarted flag
	•	Tracking P1 & P2 finish conditions
	•	Updating score
	•	Emitting showResults binding for SwiftUI sheets
	•	Notifying when a round is complete for ads

⸻

3.2 PlayerInput

State object mapping touch regions to booleans:
	•	p1Left, p1Right
	•	p2Left, p2Right

Recognized by both scenes inside applyLateralMovement().

⸻

4. SPRITEKIT LAYER

4.1 GameScene

The entire gameplay world.

Responsibilities:
	•	Road geometry (playableRect)
	•	Car rendering (PNG or primitive)
	•	Dashes / start line / finish line
	•	Forest / background art (solo)
	•	Enemy objects (obstacles)
	•	Collision detection
	•	Speed curve based on:
	•	difficulty
	•	elapsed time (stage 0 → 1 → 2)
	•	penalties
	•	Score tracking handoff to coordinator

⸻

4.2 Game Modes

.versus
	•	Left and right lanes behave independently
	•	Obstacles move downward/upward
	•	Race ends when both lanes reach finish
	•	Sportier pacing but fewer animated obstacles
	•	Ads after each completed round

.solo

Adds:
	•	Narrower lane
	•	Background forest strips
	•	Animated tumbleweeds
	•	Live-behaving squirrels (hops, panic hop, sniff, blink, dash bursts)
	•	Obstacle density increased on higher difficulties
	•	Music always replays after ads
	•	Solo scoring and leaderboard

⸻
5. OBSTACLE SYSTEM

Obstacle kinds

cone
box
tumbleweed
squirrel
pothole
rock
oilSlick
slowTruck

Spawn logic
	•	Spawn interval dynamically adjusted:
	•	Stage-based (time in run)
	•	Difficulty-based
	•	Solo-mode modifier

Motion
	•	Scrolls downward/upward based on lane
	•	Solo-mode extras:
	•	Tumbleweeds: drift, spin, clamp to road
	•	Squirrels: hops, panic hops, facing direction, idle sniff/blink, rare dash

⸻

6. DIFFICULTY MECHANICS

Two composited systems:

6.1 Speed Curve
	•	baseSpeed from difficulty
	•	Multiplied by:
	•	modeMultiplier (solo is slightly faster)
	•	stageBoost (time-in-run)
	•	penalty easing

6.2 Spawn Rate Scaling

spawnInterval = baseInterval * combinedSpawnScale

Where:
	•	stageSpawnScale (based on elapsed time)
	•	diffSpawnScale (based on difficulty)
	•	Solo mode multiplies difficulty scaling for denser spawns

⸻

7. WORLD SIMULATION

7.1 Forest (Solo Mode Only)
	•	Procedurally generated trees
	•	Multi-blob canopies (3–5 shapes)
	•	Static squirrels occasionally perched
	•	Moves at the same rate as road scroll

7.2 Dash lines
	•	Based on phase offset, infinite scrolling effect

7.3 Start & Finish lines
	•	Removed once scrolled past visible region

⸻

8. ADS SYSTEM

Components:
	•	AdPresenter — invisible UIViewController that handles:
	•	Listening to notifications
	•	Muting/unmuting background music
	•	AdManager — loads Google AdMob interstitials:
	•	preload()
	•	noteRoundCompleted()
	•	presentIfAllowed()

Rules:
	•	Ads disabled if purchased IAP hasRemovedAds
	•	Ads appear after results dismissal
	•	Ads muted background music automatically

⸻

9. AUDIO SYSTEM

Background Music (BGM)
	•	Plays via AVAudioPlayer
	•	Fades on countdown
	•	Fully muted during ads
	•	Volume restored after ad close
	•	Solo mode restarts BGM per run

Effects
	•	Crash
	•	Countdown ticks
	•	“Go” tail sound
	•	Engine loop per lane (if enabled)

⸻

10. FUTURE-PROOFING & EXTENSIONS

Suggested future systems that can be slotted in easily:

🚧 1. Power-ups
	•	Temporary invincibility
	•	Slow motion
	•	Score multiplier
	•	Magnetic score pickup

🪙 2. Unlockable cars
	•	Based on level-up streaks
	•	Different stats: acceleration / turn speed / hitbox size

🎯 3. Mission system (daily, weekly)

Examples:
	•	“Avoid 20 squirrels in one run”
	•	“Score 80 on Hard”
	•	“Play 5 rounds in a day”

🗺️ 4. Biomes

Different world themes:
	•	Desert
	•	Forest
	•	Snow
	•	Night-time neon city

🧠 5. Smarter AI obstacles
	•	Trucks that switch lanes
	•	Squirrels that coordinate or move in groups
	•	Tumbleweed tornado events (rare)

📱 6. Haptics

Add subtle impact, skid, and reward haptics.

⸻

11. FILE LIST (ORGANIZED)
SwiftUI/
  HomeView.swift
  ContentView.swift     (2-player)
  SoloGameView.swift    (single-player)
  SettingsView.swift
  HighScoresView.swift
  PlayerControls.swift
  PlayerControlsMirrored.swift
  CountdownOverlay.swift

SpriteKit/
  GameScene.swift
  SquirrelBehaviors.swift (optional future extraction)
  ForestBuilder.swift (optional future extraction)

Systems/
  GameCoordinator.swift
  PlayerInput.swift
  SpeedLevel.swift
  BGM.swift
  AdManager.swift
  AdPresenter.swift
  SoloHighScoresStore.swift
  HighScoresStore.swift
  SettingsStore.swift

Assets/
  Car PNGs
  Engine loop sound files
  Crash sound


⸻

12. SUMMARY

CoopRacer now has:
	•	Strong, modular architecture
	•	Clean separation between SwiftUI & SpriteKit
	•	Dynamic difficulty system
	•	Animated obstacles
	•	Forest background system
	•	Robust ad integration
	•	Good extension points for new features

This file should serve as your master reference for future enhancements, debugging, and onboarding collaborators.