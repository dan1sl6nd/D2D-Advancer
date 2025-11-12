# Area Recommendations Feature Guide

## Overview

The Area Recommendations system helps you identify the best neighborhoods for door-to-door sales based on external demographic data (income, home values, population density) combined with your historical performance data.

## Features Implemented

### 1. **External Data Integration**
- **US Census Bureau API**: Provides demographic data including:
  - Median household income
  - Population density
  - Home ownership rates
- **FCC Census Block API**: Converts coordinates to census tracts
- **Data Caching**: All neighborhood data is cached for 30 days to minimize API calls

### 2. **Smart Scoring System**
The system scores neighborhoods 0-100 based on:
- **Income Match (30%)**: How well the neighborhood income matches your target range
- **Population Density (20%)**: Optimal density for door-to-door (2,000-8,000 people)
- **Home Value Match (25%)**: Alignment with your target home value range
- **Your Conversion Rate (25%)**: Historical success rate in that neighborhood

### 3. **Target Demographics Preferences**
Configure your ideal customer profile:
- **Income Range**: Set min/max target income ($20k-$500k)
- **Home Value Range**: Set min/max target home values ($50k-$2M)
- **Quick Profiles**: Pre-configured for common industries:
  - Solar Panels: $100k-$150k income, $250k-$500k homes
  - Roofing: $60k-$100k income, $250k-$500k homes
  - HVAC: $100k-$150k income, $250k-$500k homes
  - Landscaping: $100k-$150k income, $500k-$750k homes
  - Pools & Spas: $150k-$250k income, $750k-$1M homes
  - And more...

## How to Use

### Access Best Areas
1. Open the app
2. Go to the **More** tab (bottom right)
3. Tap **"Best Areas"**
4. The system will analyze neighborhoods based on your existing leads

### Configure Your Target Demographics
1. In the Best Areas view, tap the **slider icon** (top right)
2. Choose a **Quick Profile** that matches your business, or
3. Manually adjust:
   - Income range sliders
   - Home value range sliders
   - Homeownership preference
4. Tap **"Done"** to save

### View Recommendations
- **Top 10 neighborhoods** are ranked and displayed
- Each shows:
  - Area name and location
  - Score (0-100) with color coding:
    - 🟢 Green (90-100): Excellent match
    - 🟡 Yellow (60-89): Good match
    - 🟠 Orange (45-59): Fair match
    - 🔴 Red (0-44): Poor match
  - Median income
  - City/State

### View Neighborhood Details
Tap any neighborhood to see:
- **Interactive map** showing the area
- **Full demographics**:
  - Median household income
  - Average home value
  - Population
  - Homeownership rate
- **Your performance** (if you have leads there):
  - Total leads
  - Converted leads
  - Interested leads
  - Conversion rate
- **Navigate button**: Opens Apple Maps with driving directions

### Map Overlay Visualization
1. Go to the **Map** tab
2. Tap the **map overlay button** (right side, top)
3. Color-coded circles show neighborhood scores:
   - Larger circles = neighborhood boundaries
   - Colors match the scoring system
4. Tap the **info button** to see the legend
5. Move the map to load new neighborhoods

## Data Sources

### Census Bureau (Free, No API Key Required)
- **API**: American Community Survey (ACS) 5-Year Estimates
- **Data Provided**:
  - Median household income
  - Total population
  - Median home values
  - Housing occupancy rates
- **Update Frequency**: Annual updates from Census Bureau
- **Coverage**: All US locations

### FCC Census Block API (Free)
- **API**: Federal Communications Commission Geocoding API
- **Purpose**: Converts GPS coordinates to census tract IDs
- **Coverage**: All US locations

## How Scoring Works

### Example Calculation
Let's say you're selling solar panels and target:
- Income: $100k-$150k
- Home values: $250k-$500k

**Neighborhood A:**
- Income: $120k ✓ (perfect match: 100 points × 30% = 30)
- Population: 5,000 ✓ (optimal suburban: 100 points × 20% = 20)
- Home value: $350k ✓ (perfect match: 100 points × 25% = 25)
- Your conversion: 15% (3/20 leads) ✓ (good rate: 70 points × 25% = 17.5)
- **Total Score: 92.5** 🟢 Excellent

**Neighborhood B:**
- Income: $75k (below target: 60 points × 30% = 18)
- Population: 15,000 (too dense: 70 points × 20% = 14)
- Home value: $180k (below target: 50 points × 25% = 12.5)
- No leads yet (neutral: 50 points × 25% = 12.5)
- **Total Score: 57** 🟠 Fair

## Tips for Best Results

1. **Add leads first**: The system needs your existing lead locations to fetch neighborhood data
2. **Set realistic ranges**: Use the Quick Profiles as a starting point
3. **Check regularly**: Neighborhoods are re-scored as you add more leads
4. **Use the map overlay**: Visual representation helps identify clusters
5. **Review your performance**: Tap neighborhoods where you've already worked to see your success rate

## Technical Details

### Data Storage
- **CoreData entity**: Neighborhood
- **Caching**: 30-day expiration
- **Sync**: Integrates with Firebase sync (if enabled)

### Files Created
1. **Neighborhood** (CoreData entity): Stores neighborhood demographics
2. **NeighborhoodDataService.swift**: Handles API calls and caching
3. **NeighborhoodScoreEngine.swift**: Scoring algorithm
4. **TargetDemographicsPreferences.swift**: User preferences management
5. **AreaRecommendationsView.swift**: Main recommendations UI
6. **NeighborhoodDetailView.swift**: Detailed neighborhood view
7. **DemographicsPreferencesView.swift**: Settings UI
8. **NeighborhoodOverlayView.swift**: Map overlay components

### API Limitations
- **Census Bureau**: No rate limits (public API)
- **FCC API**: No rate limits (public API)
- **Network required**: Initial data fetch requires internet
- **US only**: Currently supports US locations only

## Future Enhancements (Not Yet Implemented)

### Potential Additions:
1. **Additional Data Sources**:
   - Zillow API for real-time home values
   - Attom Data API for property details
   - Weather patterns
   - Crime statistics

2. **Advanced Features**:
   - Time-of-day recommendations
   - Seasonal analysis
   - Route optimization within top neighborhoods
   - Export neighborhood reports to PDF

3. **International Support**:
   - Canada census data
   - UK postcode data
   - Australia ABS data

## Troubleshooting

### "No Areas Found"
- **Solution**: Add some leads first, then return to Best Areas
- The system needs locations to analyze

### Neighborhoods not loading on map
- **Solution**:
  1. Ensure you have internet connection
  2. Toggle the overlay off and back on
  3. Try zooming to a different area

### Incorrect scores
- **Solution**:
  1. Adjust your target demographics
  2. Ensure leads have accurate addresses
  3. Wait for more lead data to improve accuracy

### API Errors
- **Census data failed**: Check internet connection, API may be temporarily down
- **Coordinates not found**: Ensure leads have valid GPS coordinates

## Privacy & Data

- All demographic data is **public information** from US Census
- No personal information is collected or sent to external APIs
- GPS coordinates are only used to fetch neighborhood-level data
- All data is cached locally on device and in your Firebase account (if synced)

## Support

For issues or feature requests related to the Area Recommendations system:
1. Check the error messages in the console
2. Verify your leads have valid addresses and coordinates
3. Report issues at: https://github.com/anthropics/claude-code/issues