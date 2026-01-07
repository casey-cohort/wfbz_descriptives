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
- [X] Add column percentages to cells (format: n=119 (33%))
- [X] Keep figure for reference, plan to write summary sentence

### Ignition Dates of Disaster Fires by Year
- [x] Remove outline of boxes
- [x] Make whiskers thinner
- [x] Remove vertical space between boxes (blend them together)
- [x] Remove uncertainty band around loess/line of best fit
- [x] Order by median start date in 2000
- [x] Change median line in boxes to a dot
- [ ] After above fixes: Try geofaceting by state (color state plots by region)
- [x] Remove x-axis label

#### After meeting

- [x] percents in table are wrogn
- [x] fatalities per 100k seem wrong in table
- [ ] 2011 and 2012 seem to be missing from fatalities over time (missingness the problem???)
- [x] find average acrage of a disaster fire by region instead of this tihng about total area
- [x] remove "new" wui impacting plots
- [x] remove "all" columns from wui plots -- make it not just one column

### Next Meeting

- [x] move missingness to bottom of table
- [x] what's going on with that really big avg fire size in 04 in alaska?
- [x] wui plots -- make 3x5 or whatever
- [z] fix text formatting in cat variables compared
- [x] cat variables compared, do percentages as row percent not total
- [x]  seasonal timing make 2x5 and make em a little narrower
- [x] in stacked plots change order so ca always on bottom, then be consistent with order throughout

### Still to do

- [x] figure out fatalities
- [x] make sure yarnell hill fire label doesn't need to move
- [x] rm x axis label, word "percent" in y axis label in WUI plots, change background to white
- [x] remove fire season box, make it two by five
- [x] rm year x axis label from variables over time
- [x] variables over time fema plot , y axis to "fema declarations, n"


### FEMA

in maps: make states unfilled and bring lines to front

- [ ] Some figure showing FEMA declarations over time by region or state, maybe total
- [ ] Scatter # of fema dec vs # of fires and other measures (total by state)
- [ ] bivariate map of fema vs (whatever) e.g. https://giscarta.com/blog/bivariate-choropleth-maps-a-comprehensive-guide. County or sub-state-sized grid *** NOTE: try state instead, try to fix quartile ***
- [ ] do a version of the variables over time plot for fema but as a line plot not stacked
- [ ] add area burned
- [ ] stack rank percentage of fema decs by state
