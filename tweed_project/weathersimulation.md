# Carrier Command 2 — Weather & Ocean Simulation

*Summary of "The Making of Carrier Command 2: Ocean and Weather Simulation" by Geometa*

---

## Overview

This is a 17-minute developer walkthrough by Geometa (the studio behind Stormworks and Carrier Command 2) showing the weather and ocean simulation systems in CC2. Two developers have an informal chat walking through the debug tools, explaining how each system works and how it affects gameplay.

The key takeaway: CC2 uses a **2D fluid simulation** running at **2 ticks per second** to drive wind, rain, fog, and ocean currents across a **~256 km world**. Weather data is stored in GPU textures with RGB channels encoding different properties. The ocean uses **Gerstner waves** (not FFT) with **level-of-detail subdivision**. The entire simulation is **deterministic** — clients receive the initial state on join and simulate identically to the server.

---

## 1. Fluid Simulation — The Core Engine

Everything weather-related is driven by a single **2D fluid simulation** that pushes particles around the world grid.

**Key details from the developer:**
- The simulation runs at **2 updates per second** — deliberately slow because weather changes minute-by-minute, not second-by-second
- It's described as "pushing particles around in a kind of 2D sense" with flow that is "modifying and continuing to develop"
- Vortices form and swirl organically over time
- The simulation **wraps around** — the texture edges connect, so weather flows seamlessly across world boundaries
- Inspiration cited: **windy.com** — the real-world weather visualisation site was a direct reference for both the simulation behaviour and the particle-based map visualisation

**Deterministic sync model:**
- Weather state is synchronised when players join a multiplayer game
- The simulation is **deterministic** — once a client receives the initial state, it simulates forward identically to the server without needing continuous sync
- This is critical for multiplayer: all players see the same weather at the same time

---

## 2. Weather Data Layers

The weather system stores multiple data layers as **GPU textures**, with RGB channels encoding different properties. The developer walks through the debug visualisations showing each layer.

### 2.1 Wind

- Visible as swirling patterns on the tactical map with areas of high wind and low wind
- The wind layer **drives the other layers** — it pushes rain, fog, and weather patterns around the world
- Players can read the wind data to predict where weather will move: "if you look at the wind data you can predict to some effect where the weather is going to move"
- Wind directly pushes aircraft and the carrier on the water

### 2.2 Rain / Precipitation

- Stored as a separate layer with varying intensity
- The developer estimates roughly **2/3 of the map has no rain**, with 1/3 having rain coverage at any given time
- Precipitation ranges from light rain to heavy storms
- At **very high precipitation levels**: thunderstorms with lightning are triggered
- At high precipitation: **radar doesn't work** due to electrical interference (gameplay mechanic)
- The organic swirling patterns are "entirely generated from the fluid simulation"

### 2.3 Fog

- Fog is **advected (pushed) by the wind** layer — "the wind is pushing the fog around the world"
- The fog and wind layers share certain patterns in common because of this relationship
- Fog affects **visibility** — a direct gameplay impact for detection and stealth

### 2.4 Ocean Depth (Static)

- Ocean depth is **not part of the fluid simulation** — it's a static data layer
- However, it **influences the ocean current simulation**: shallower water dampens current flow
- Islands resist and reduce current flow where the water is shallow
- Currents flow most easily through the **deepest areas** and tend to push between islands, splitting and merging around landmasses

---

## 3. Ocean Current Simulation

Ocean current is a **separate layer** from the wind/rain/fog weather system — it runs independently.

**How it works:**
- Also fluid-simulation-driven, updating at **2 ticks per second**
- Current data is stored in a texture where **Red = X-direction flow** and **Green = Y-direction flow** (the developer confirms: "red and green is the direction")
- Values go above 1.0 and into negative, so the full range isn't visible in a standard RGB texture view — black areas represent negative flow values
- The texture wraps around, matching at edges
- More detail appears around islands where flow is complex (splitting, merging, being dampened by shallow water)

**Gameplay impact — this is significant:**
- Strongest currents estimated at roughly **20 knots**
- Players can catch currents to gain ~20 knots of free speed toward objectives
- Going against current is significantly slower
- In PVP: players can use currents tactically — try to push enemies into unfavourable currents, or use currents to escape
- The current overlay is available on the in-game map for strategic planning

---

## 4. Ocean Rendering

The developer explicitly states that **CC2's ocean is entirely new code** — not shared with Stormworks despite being from the same studio.

### 4.1 Wave Algorithm: Gerstner Waves

- Confirmed as **"simple Gerstner waves"** (not FFT-based)
- Simulated at **2 ticks per second** (vs Stormworks which simulates at 60 ticks/second)
- The wave texture is **larger in scale** than Stormworks — more data per texture means less visible repetition
- Trade-off: less small-scale wave detail, but much better large-scale ocean with bigger waves
- The developer notes it's "very difficult to see any kind of repeating quality" compared to Stormworks where you can "start to see certain waves appearing on a grid"

### 4.2 Level of Detail (LOD) Subdivision

- The ocean mesh uses **LOD subdivision** — triangles double in detail as the camera gets closer
- Blending zones smooth transitions between LOD levels
- Further from the camera = fewer, larger triangles; close to camera = fine mesh
- This is described as "a pretty common technique in game development" also used for terrain
- Essential for CC2 because the **view distance is enormous** — the carrier is several hundred metres long but you can see all the way to the horizon with ocean rendering the entire way

### 4.3 Ocean Textures (Debug View)

Three textures visible in the debug overlay:

| Texture | Contents | Notes |
|---------|----------|-------|
| Top | Ocean depth | Static bathymetry data |
| Middle | Wave data | Gerstner wave displacement — larger scale than Stormworks |
| Bottom | Ocean current | RGB-encoded: R = X-direction, G = Y-direction, values exceed 0–1 range |

---

## 5. Visualisation System

The tactical map visualisation (the holographic table on the carrier bridge) uses a **particle system inspired by windy.com**.

- Small particles flow across the map surface following wind/current vectors
- Particles visualise direction of flow for both wind and ocean currents
- Different map modes cycle through the data layers: wind, rain, fog, ocean current, ocean depth
- The developer switches between modes live, showing how each layer provides different strategic information

---

## 6. Gameplay Impact Summary

The developers emphasise that weather isn't just visual — it has real tactical consequences:

| System | Gameplay Effect |
|--------|----------------|
| **Wind** | Pushes aircraft and carrier; affects navigation |
| **Ocean current** | Up to ~20 knots speed boost or penalty; major strategic factor in PVP |
| **Rain** | At high levels, disables radar (electrical interference) |
| **Fog** | Reduces visibility and detection range |
| **Thunderstorms** | Triggered by very high precipitation; radar blackout |
| **Day/night cycle** | Interacts with all systems to create constantly changing conditions |

The developer notes: "having a 10% advantage by using the weather to your benefit can be the difference between victory and defeat" — particularly in PVP scenarios.

---

## 7. Architecture Summary

```
         2D Fluid Simulation (2 ticks/sec, wrapping texture)
                    │
     ┌──────────────┼──────────────┐
     ▼              ▼              ▼
   Wind           Rain           Fog
  (drives      (intensity →    (advected
   others)     storms/radar)   by wind)
     │              │              │
     ▼              ▼              ▼
  Aircraft      Lightning      Visibility
  push          triggers       reduction
     │
     ▼
  Weather advection
  (wind pushes rain + fog patterns)

         Separate Fluid Simulation (2 ticks/sec)
                    │
                    ▼
             Ocean Current
          (R=X dir, G=Y dir)
                    │
       ┌────────────┼────────────┐
       ▼            ▼            ▼
    Ship speed   Dampened by   Wraps around
    ±20 knots    shallow water  world edges
                 (island proximity)

              Ocean Depth (Static)
                    │
                    ▼
            Influences current
            dampening + flow paths

           Gerstner Waves (2 ticks/sec)
                    │
                    ▼
        Ocean Mesh with LOD Subdivision
        (larger texture = less repetition)
                    │
                    ▼
         Rendering Pipeline
         (Bloom, FXAA, Tonemap, Particles)
                    │
                    ▼
          Tactical Map Display
          (windy.com-style particles)
```

---

## 8. Key Technical Decisions & Trade-offs

The developer highlights several deliberate design choices:

**Low tick rate (2/sec) for weather + ocean:** Weather doesn't change second-by-second, so a slow simulation rate is both realistic and cheap. The ocean waves also only update at 2/sec (vs 60 in Stormworks) — trading temporal precision for spatial scale.

**Larger wave textures, less small-scale detail:** CC2 chose bigger waves and less repetition over the detailed small-scale waves in Stormworks. This suits the game's huge view distances and strategic carrier-scale gameplay.

**Deterministic simulation:** By making the fluid sim deterministic, they avoid constant network sync of weather state. Clients just need the starting state and simulate forward identically — elegant for multiplayer.

**Depth-dampened currents:** Rather than simulating 3D ocean physics, they simply dampen current strength based on a static depth map. Shallow water near islands = less current. Simple, effective, and creates natural-looking flow patterns around archipelagos.

**Everything is new code:** Despite being the same studio as Stormworks, CC2's ocean is a completely different implementation optimised for different requirements (scale over detail).

---

## Sources

- Video: "The Making of Carrier Command 2 — Ocean and Weather Simulation" by Geometa (YouTube)
- [Carrier Command 2 on Steam](https://store.steampowered.com/app/1489630/Carrier_Command_2/)
- [Geometa (Developer)](https://geometa.co.uk/)
- [windy.com](https://www.windy.com/) — cited by the developer as direct inspiration