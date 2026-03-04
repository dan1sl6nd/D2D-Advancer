# Territory Intelligence Design

**Date:** 2026-03-03
**Status:** Approved

## Overview

Three features that transform the map tab from a lead pin viewer into a territory intelligence platform: heatmap visualization, route optimization, and customizable scoring weights.

## Feature 1: Heatmap Rendering

### Purpose
A continuous gradient overlay on the map that visualizes neighborhood scores as a smooth color field, letting salespeople instantly identify high-value territories.

### Implementation

**Custom Overlay Renderer:**
- `HeatmapOverlay` (MKOverlay) covering the visible map region
- `HeatmapOverlayRenderer` (MKOverlayRenderer) with pixel-level kernel density estimation
- Each cached Neighborhood center acts as a heat source with its score as intensity
- Gaussian falloff with ~500m radius (adjustable for suburban vs. urban density)
- Color gradient: transparent -> blue -> cyan -> green -> yellow -> orange -> violet

**Rendering Pipeline:**
1. On region change (debounced 300ms), collect all Neighborhood entities within the visible rect
2. For neighborhoods not yet cached, auto-fetch census data via existing NeighborhoodDataService
3. Build a grid of sample points across the visible area
4. For each sample point, sum Gaussian-weighted scores from nearby neighborhoods
5. Map summed values to the color gradient
6. Render in `draw(mapRect:zoomScale:in:)` with tile-based approach for performance

**Map Integration:**
- Toggle button in map FAB menu (flame icon)
- Replaces existing unused circle overlay system
- Refactor NeighborhoodOverlayManager to drive heatmap data instead of discrete circles
- Legend overlay shows the color scale with score ranges

**Performance Considerations:**
- Tile-based rendering (only redraws visible tiles)
- Debounced region change handler (300ms)
- Grid resolution scales with zoom level (coarser when zoomed out)
- Background thread for kernel density calculation

## Feature 2: Route Optimization

### Purpose
A "Start My Day" route planner that calculates the optimal visit order for selected leads, displays the route on the map, and hands off to Apple Maps for navigation.

### Lead Selection

- "Plan Route" button in map FAB menu (route icon)
- Opens a sheet with today's follow-ups pre-selected
- Users can add/remove leads manually
- Starting point: current location (default) or custom address
- Maximum stops: 50 leads per route

### Route Calculation

**Algorithm: Nearest-Neighbor Heuristic with MKDirections Refinement**
1. Start from user's current location (or custom start)
2. At each step, compute haversine distance to all unvisited leads
3. Take the top 3 closest candidates
4. Request MKDirections ETA for those 3 (parallel requests)
5. Pick the actual nearest by driving time
6. Repeat until all leads are visited

**Appointment Time Windows:**
- If a lead has a scheduled appointment, it must be visited within +/- 15 min of appointment time
- Time-windowed leads are inserted at the correct position in the route
- Route segments before and after appointments are independently optimized

**Rate Limiting:**
- MKDirections requests are batched (max 10 concurrent)
- Fallback to haversine distance when throttled
- Cache ETA results for the session (lead pairs don't change mid-route)

### Map Display

- Route polyline rendered in electric violet (3pt width)
- Numbered stop markers (1, 2, 3...) overlaid on lead pins
- Bottom sheet shows route summary:
  - Total stops, estimated total time, total distance
  - Per-stop rows: lead name, address, ETA, drive time from previous
- Sheet is dismissible but persists while route is active

### Actions

- "Navigate" button: opens Apple Maps with multi-stop waypoints
- Swipe "Skip" on any stop: recalculates route excluding that lead
- Swipe "Completed" on a stop: marks lead as visited (increments visitCount, sets lastContactDate), advances to next stop
- "End Route" button: clears route overlay and returns to normal map

## Feature 3: Scoring Weight Sliders

### Purpose
Expose the 4 neighborhood scoring weights as adjustable sliders so users can tune which factors matter most for their specific sales territory and product.

### UI (in DemographicsPreferencesView)

**New "Scoring Weights" section:**
- Placed below existing income/home value sliders
- 4 labeled sliders (0-100 each):
  - Income Weight (default: 30)
  - Population Density Weight (default: 20)
  - Home Value Weight (default: 25)
  - Conversion History Weight (default: 25)
- Stacked bar chart showing normalized proportions visually
- "Reset to Defaults" button
- Auto-normalization: adjusting one slider redistributes others proportionally to maintain 100% total

**Live Preview:**
- Sample score calculation using a representative neighborhood
- Updates in real-time as sliders move
- Shows component breakdown (e.g., "Income: 28pts, Density: 15pts, Value: 22pts, Conversion: 20pts = 85")

### Integration

- Reads/writes existing `@AppStorage` keys: `weightIncome`, `weightDensity`, `weightHomeValue`, `weightConversion`
- `NeighborhoodScoreEngine` already consumes these values
- On weight change: all cached neighborhood scores recalculate, heatmap redraws

### Industry Preset Updates

Existing profiles (Solar, Roofing, HVAC, etc.) updated with recommended weights:

| Profile | Income | Density | Home Value | Conversion |
|---------|--------|---------|------------|------------|
| Solar Panels | 35 | 15 | 35 | 15 |
| Roofing | 25 | 20 | 30 | 25 |
| HVAC | 30 | 20 | 25 | 25 |
| Windows & Doors | 25 | 20 | 30 | 25 |
| Landscaping | 25 | 10 | 40 | 25 |
| Home Remodeling | 30 | 15 | 35 | 20 |
| Security Systems | 30 | 25 | 20 | 25 |
| Pools & Spas | 25 | 10 | 40 | 25 |
| Toronto General | 30 | 20 | 25 | 25 |
| Toronto Premium | 25 | 15 | 40 | 20 |

## Architecture Notes

**Existing code reuse:**
- NeighborhoodOverlayManager refactored (not replaced) to serve heatmap data
- NeighborhoodDataService unchanged (US Census + Canadian APIs)
- NeighborhoodScoreEngine unchanged (already reads weight AppStorage keys)
- LocationManager unchanged (provides user location for route start)

**New files:**
- `HeatmapOverlay.swift` - MKOverlay subclass
- `HeatmapOverlayRenderer.swift` - pixel rendering + kernel density
- `RouteOptimizer.swift` - TSP solver + MKDirections integration
- `RoutePlannerView.swift` - lead selection sheet + route summary
- `ScoringWeightsView.swift` - weight sliders + stacked bar + live preview

**Modified files:**
- `MapView.swift` - FAB menu additions (heatmap toggle, route button), overlay rendering
- `DemographicsPreferencesView.swift` - scoring weights section
- `NeighborhoodOverlayManager.swift` - refactor for heatmap data provider role
- `CustomizableThemeManager.swift` - route polyline and numbered marker styles
