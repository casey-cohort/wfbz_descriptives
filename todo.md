## Immediate Tasks
- [ ] Create spaghetti plot
- [ ] Create WUI map
- [X] Add Hawaii and Alaska to WUI visualizations
- [X] Continue checking for missing 2024 data (may be incorporated by agencies later) _Assume this isn't happening right now_

## Plot Revisions & Feedback to Incorporate

### Fires per Area Analysis
- [ ] _Add sentence explaining fires per 100,000 acres to scale for state/region size_
- [X] Add fatalities per 100k people metric with explanation

### Number of Structures Destroyed (Region Over Time)
- [ ] _Investigate why Southwest isn't labeled as top region for destroyed structures_ **I only labeled the top five fires.**

### Burned Area Over Time
- [ ] _Add metric for percent of available sq km burned_

### WUI Plots
- [X] Remove panel of 4 WUI plots (for both interface and intermix)
- [X] For "Share of fires in WUI": Convert from faceted bar plots to single plot with colored dots/lines for each region (pink for CA, purple for SW, etc.) on same x and y axes **Mocked up, but not sure how I feel about it**

### Numeric Values Compared Plot
- [ ] Fix clustering issue - investigate why scale differs between panels (e.g., row 1 panel 1 vs panel 3) **Could add noise to eliminate rounding issue (lines are at whole numbers of acres).**
- [ ] Standardize scale for area across panels to avoid artificial clustering effect

### Numeric & Categorical Values Compared
- [X] Add color coding by FEMA Y/N and WUI variables
- [ ] Consider using violin plots
- [X] Flip FEMA declaration order (TRUE first) so gradient matches in top and bottom panels

### Categorical Values Compared Heat Plot
- [ ] Add column percentages to cells (format: n=119 (33%))
- [ ] Keep figure for reference, plan to write summary sentence

### Ignition Dates of Disaster Fires by Year
- [ ] Remove outline of boxes
- [ ] Make whiskers thinner
- [ ] Remove vertical space between boxes (blend them together)
- [ ] Remove uncertainty band around loess/line of best fit
- [ ] Order by median start date in 2000
- [ ] Change median line in boxes to a dot
- [ ] After above fixes: Try geofaceting by state (color state plots by region)
- [ ] Remove x-axis label
