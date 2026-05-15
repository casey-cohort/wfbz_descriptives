# WFBZ pipeline orchestration.
#
# `make` (fast path) assumes the manually-downloaded raw data, the external
# rasters (ghs_pop, WUI), and the committed tiger_states.geojson /
# regions.geojson are present, then runs the cheap deterministic staging and
# renders the site. The expensive download/API staging steps (tracts, whp,
# population, wui) are opt-in targets and are NOT prerequisites of `all`.
#
# Python steps need the `wfbz` conda env active (popexposure). See CLAUDE.md.
#
# Hybrid design: cheap local steps are file targets (rebuilt only when their
# prerequisites change); the download/API steps and `quarto render` (no single
# output) are phony. File targets name one representative of each recipe's
# co-produced outputs.

R    := Rscript
PY   := python
PROC := data/processed
NHGIS := $(PROC)/nhgis

WFBZ         := data/raw/wfbz_disasters_2000-2025.geojson
TIGER_STATES := data/raw/tiger_states.geojson
REGIONS      := $(PROC)/regions.geojson
TRACT_WHP    := $(PROC)/tract_WHP_AK.geojson $(PROC)/tract_WHP_HI.geojson $(PROC)/tract_WHP_CONUS.geojson
HEXGRID      := $(PROC)/hexgrid.geojson
BY_WF        := $(NHGIS)/race_by_wf.parquet            # + poverty/vehicle/housing_by_wf
BOOTSTRAP    := $(PROC)/diverge_bootstrap.parquet
POP_AFFECTED := $(PROC)/pop_affected.csv               # + 8 more CSVs + abstract.txt

.PHONY: all render hexgrid spatial-join bootstrap abstract \
        tracts whp population wui check-prereqs check-nhgis clean help

all: render

# ── Fast-path file targets ───────────────────────────────────────────────────

$(HEXGRID): staging/prep_hexgrid.R $(TIGER_STATES)
	$(R) staging/prep_hexgrid.R

$(BY_WF): staging/prep_spatial_join.R $(TRACT_WHP) $(WFBZ) | check-nhgis
	$(R) staging/prep_spatial_join.R

# B is read from $WFBZ_BOOT_B (default 100); override: WFBZ_BOOT_B=1000 make bootstrap
$(BOOTSTRAP): staging/prep_diverge_bootstrap.R $(TRACT_WHP) $(REGIONS) $(WFBZ) | check-nhgis
	$(R) staging/prep_diverge_bootstrap.R

$(POP_AFFECTED): staging/abstract.py $(WFBZ) $(REGIONS) $(HEXGRID)
	$(PY) staging/abstract.py

# ── Phony convenience aliases ────────────────────────────────────────────────

hexgrid:      $(HEXGRID)
spatial-join: $(BY_WF)
bootstrap:    $(BOOTSTRAP)
abstract:     $(POP_AFFECTED)

# `quarto render` has no single file output → phony. Runs after staging.
render: check-prereqs hexgrid spatial-join bootstrap abstract
	quarto render

# ── Expensive opt-in staging (NOT prerequisites of `all`) ────────────────────

tracts:     ; $(R) staging/prep_tracts.R
whp:        ; $(PY) staging/prep_whp.py
population: ; $(R) staging/prep_population.R
wui:        ; $(R) staging/prep_wui.R

# ── Guards (fast path assumes these external/committed inputs exist) ──────────

check-prereqs:
	@test -f $(WFBZ) || { echo "MISSING $(WFBZ) -- download from Harvard Dataverse (see CLAUDE.md)"; exit 1; }
	@test -f $(TIGER_STATES) || { echo "MISSING $(TIGER_STATES) -- render once so _setup.qmd creates it"; exit 1; }
	@test -f $(REGIONS) || { echo "MISSING $(REGIONS) -- render once so _setup.qmd creates it"; exit 1; }

check-nhgis:
	@test -f $(NHGIS)/race.parquet || { echo "MISSING $(NHGIS)/*.parquet -- run 'make population' (IPUMS API)"; exit 1; }

clean:
	rm -f $(HEXGRID) $(BOOTSTRAP) $(PROC)/pop_affected*.csv $(PROC)/abstract.txt
	rm -rf rendered

help:
	@echo "make                fast path: staging -> quarto render"
	@echo "make hexgrid|spatial-join|bootstrap|abstract   individual staging steps"
	@echo "make render         quarto render (after staging)"
	@echo "make tracts|whp|population|wui   expensive opt-in downloads / API"
	@echo "make clean          remove cheap regenerable outputs + rendered/"
