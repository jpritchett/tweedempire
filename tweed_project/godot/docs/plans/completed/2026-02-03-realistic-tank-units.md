# Add Realistic Tank Units with Imported 3D Models

Replace the existing fictional units (stitchhand_constructor, bobbinscout_skimmer, shuttle_gunner) with realistic tank units from real nations (T-90, M1 Abrams, Challenger 2). Set up a model loading system for .glb files with proper asset organization.

## Context

- Files involved: data/unit_defs.json, src/world/unit_view.gd, scenes/unit_view.tscn
- New directories: assets/models/units/
- Related patterns: Registry loads unit definitions from JSON, unit_view.gd handles visual representation
- Dependencies: Free .glb tank models (from Kenney.nl or OpenGameArt.org)

## Implementation Approach

- Add a "model" field to unit definitions in JSON
- Modify unit_view.gd to load .glb models dynamically based on unit definition
- Keep the BoxMesh as a fallback when model is not found
- Test with placeholder models first, then add real tank models

## Tasks

### Task 1: Set up model loading infrastructure

**Files:**
- Modify: `src/world/unit_view.gd`
- Modify: `scenes/unit_view.tscn`

**Steps:**
- [x] Add a model_path property to unit_view.gd
- [x] Create a set_model(path: String) function that loads a .glb file and replaces the mesh
- [x] Keep existing BoxMesh as default fallback
- [x] Test that the fallback still works

### Task 2: Update unit definitions with tank units

**Files:**
- Modify: `data/unit_defs.json`

**Steps:**
- [x] Replace stitchhand_constructor with t90_tank (Russian T-90, role: heavy)
- [x] Replace bobbinscout_skimmer with m1_abrams (US M1 Abrams, role: main_battle)
- [x] Replace shuttle_gunner with challenger2 (British Challenger 2, role: main_battle)
- [x] Add "model" field to each unit pointing to assets/models/units/{name}.glb
- [x] Adjust stats (hp, speed, cost) to reflect tank characteristics

### Task 3: Add tank model assets

**Files:**
- Create: `assets/models/units/` directory
- Add: .tscn files for each tank (procedural models)

**Steps:**
- [x] Create the assets/models/units/ directory
- [x] Create procedural tank models as .tscn scene files
- [x] Import as t90_tank.tscn, m1_abrams.tscn, challenger2.tscn
- [x] Verify models import correctly in Godot

### Task 4: Wire up model loading in unit spawning

**Files:**
- Modify: `src/world/world.gd` (if unit spawning happens there)

**Steps:**
- [x] When spawning a unit, read the "model" field from Registry.get_unit_def()
- [x] Call unit_view.set_model() with the model path
- [x] Test that each tank type displays its correct model

## Verification

- [x] Run the game and spawn each tank type
- [x] Verify T-90, M1 Abrams, and Challenger 2 each show their distinct model
- [x] Verify fallback works when model file is missing
- [x] Verify selection highlighting still works on 3D models

## Completion

- [x] Move this plan to `docs/plans/completed/`
