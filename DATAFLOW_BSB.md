# BSB: Data Flow & Execution Order

Companion document: [`README.md`](README.md) (orientation + onboarding).

---

## Executive Summary

The repository contains **four confirmed wrapper scripts** (two R `source()` wrappers, two bash `Rscript` wrappers) plus **three candidate** orchestrators whose status is not settled. Across the repo there are **55 `.R` files, 13 `.do` files, 19 `.Rmd` files, 2 `.sh` files, and 2 `.ado` programs** — 91 scripts in all, of which about 25 are reachable from a wrapper. The remainder are hand-run.

**Confidence in the reconstructed order is high for the wrapped segments and moderate-to-low for the rest.** The wrapped segments (commercial processing, tilefish processing, the random-forest post-processing batch) state their own order explicitly and are trustworthy. Outside those, ordering was inferred from data-file dependencies, and several scripts have no traceable link to the rest of the pipeline at all.

**Ten open issues are catalogued below** (F-1 … F-10), ranging from a vintage skew between the R and Stata halves of the pipeline to a source loop that executes a driver script as a side effect.

Three structural facts dominate everything below and should be read before the detail sections:

1. **The R `A01`–`A04` chain is the live commercial-processing path; the Stata `A01`–`A04` chain is retired**, marked as such at `00_commercial_processing_wrapper.do:1`. Both write the same file stems, differing only in extension (`.dta` vs `.Rds`); only the `.Rds` side is current. The retirement covers commercial *processing* only — the Stata *analysis* chain (`00_analysis_wrapper.do` and its five do-files) is live, and consumes `.dta` files written by `B01_data_prep_ml.R:507`.
2. **Stata passes vintages by explicit global macro; R passes them by scanning the disk.** Every downstream R script re-derives `vintage_string` with `list.files(...) |> max()`. This means the R wrapper's `vintage_string` assignment does **not** propagate past the `A0*` scripts — `B01` silently overwrites it. These are genuinely different mechanisms and are documented separately.
3. **`$in_string` is assigned a different value by each live wrapper**, pointing each pipeline at a different DataPull vintage (`2026-03-16` for the Stata analysis chain, `2026-05-01` commercial, `2026-06-09` tilefish). All live assignments now share one format; the odd underscore form survives only in the retired wrapper. Flagged, not resolved — see [Flag F-1](#f-1-in_string-points-each-pipeline-at-a-different-vintage).

---

## Wrapper Inventory

---

#### 1. `R_code/data_extraction_processing/processing/commercial/00_commercial_processing_wrapper.R`

Sets vintage variables, loads shared helpers, then `source()`s six scripts in order.

Scripts it calls, in order:

| # | Script | Line |
|---|---|---|
| — | `R_code/analysis/helpers/gear_market_helpers.R` *(helper, not a stage)* | `:33` |
| 1 | `commercial/A01_make_landings_cleaned.R` | `:35` |
| 2 | `commercial/A02_make_daily_stats.R` | `:36` |
| 3 | `commercial/A03_make_dealer_stats.R` | `:37` |
| 4 | `commercial/A04_make_moving_average_prices.R` | `:38` |
| 5 | `commercial/B01_data_prep_ml.R` | `:42` |
| 6 | `commercial/B02_handle_not_in_estimation_dataset.R` | `:45` |

**Toggles / configuration found:**

| Name | Line | Default | What it gates |
|---|---|---|---|
| `in_string` | `:29` | `"2026-05-01"` | Vintage suffix of the **input** files read from the external DataPull repo. Comment says "matches Stata `in_string`". |
| `vintage_string` | `:30` | `Sys.Date()` | Vintage suffix of **output** files. **Governs only `A01`–`A04`** — `B01` overwrites it at `B01_data_prep_ml.R:66-69`. See [F-2](#f-2-r-vintage_string-is-overwritten-mid-wrapper). |
| `my_datapull` | `:25-26` | `dirname(here())/READ-SSB-Lee-BSB-DataPull` | Path to the **external** upstream repo. Sibling-directory assumption. |
| `lbs_to_kg` | `:31` | `2.20462` | Unit conversion constant used downstream. |

There are **no on/off execution toggles** in this wrapper. Every stage runs unconditionally; the only way to skip one is to comment out its `source()` line.

**Note:** the header comment at `:2-3` still says `00_commercial_processing_wrapper.R` / "R equivalent of `00_commercial_processing_wrapper.do`" — accurate here.

---

#### 2. `R_code/data_extraction_processing/processing/tilefish/00_tilefish_processing_wrapper.R`

Structurally a near-clone of the commercial wrapper.

Scripts it calls, in order:

| # | Script | Line |
|---|---|---|
| — | `R_code/analysis/helpers/gear_market_helpers.R` *(helper)* | `:35` |
| 1 | `tilefish/A01_make_tilefish_landings_cleaned.R` | `:37` |
| 2 | `tilefish/A02_make_daily_tilefish_stats.R` | `:38` |
| 3 | `tilefish/A03_make_tilefish_dealer_stats.R` | `:41` |
| 4 | `tilefish/A04_make_tilefish_moving_average_prices.R` | `:44` |
| 5 | `tilefish/B01_data_prep_tilefish_ml.R` | `:48` |
| 6 | `tilefish/B02_handle_not_in_tilefish_estimation_dataset.R` | `:51` |

**Toggles / configuration found:**

| Name | Line | Default | What it gates |
|---|---|---|---|
| `in_string` | `:31` | `"2026-06-09"` | Input vintage from the DataPull repo. **Differs from the commercial wrapper's `2026-05-01`.** |
| `vintage_string` | `:32` | `Sys.Date()` | Output vintage. Same overwrite caveat as commercial (`B01_data_prep_tilefish_ml.R:21-24`). |
| `tile_data_dir` | `:28-29` | `data_folder/main/tilefish` | Output directory; **created by the wrapper** via `dir.create(..., showWarnings=FALSE)`. This is the only wrapper that creates its own output folder. |
| `my_datapull` | `:25-26` | sibling `READ-SSB-Lee-BSB-DataPull` | External repo path. |
| `lbs_to_kg` | `:33` | `2.20462` | Unit conversion. |

No on/off toggles. All six stages run unconditionally.

**Known defect (cosmetic):** the header comment at `:2-3` was copied from the commercial wrapper and still reads `00_commercial_processing_wrapper.R`. The `here::i_am()` call at `:23` is correct.

---

#### 3. `R_code/analysis/fit_random_forest/batch_RF_run.sh`

This is a bash script that invokes `Rscript` and `rmarkdown::render` from the **project root**. Unlike the R wrappers, **its toggles are comment/uncomment, not variables.** Nine of eleven steps are currently enabled.

Steps, in file order, with current on/off state:

| # | Step | Lines | State |
|---|---|---|---|
| 1 | `tune_randomforest_nocluster.R` | `:19-21` | **ON** |
| 2 | `train_randomforest_nocluster.R` | `:24-26` | **ON** |
| 3 | `variable_importance_randomforest_nocluster.R` | `:29-31` | **ON** |
| 4 | `weighted_calibration.R` | `:36-38` | **ON** |
| 5 | `writing/figure1.R` | `:42-44` | **ON** |
| — | `writing/figure2.R` | `:47-49` | **OFF** — comment at `:46` says *"Figure 2 requires windows, so you have to run this by hand"* |
| 6 | render `writing/predictions_heatmap.Rmd` → html | `:52` | **ON** |
| 7 | render `writing/tuning_diagnostics.Rmd` → html | `:56` | **ON** |
| 8 | render `writing/out_of_sample_predictions.Rmd` → html | `:59` | **ON** |
| 9 | `plot_ROC_curves.R` | `:62-64` | **ON** |
| — | render `writing/Economic_informed_stock_assessments.Rmd` → pdf | `:80` | **OFF** — under a `TO DO` header, annotated *"you're not actually going to do this"* |

**This is the full end-to-end chain**: the three model-producing steps (tune → train → variable importance) feed the calibration, figure, report, and ROC steps that consume them. Nine steps run, joined by `&&`.

**Failure behaviour (`:2-3`, `:16`, `:66-72`).** `set -e` + `set -o pipefail`, and the nine steps are `&&`-chained, so a failed step halts the batch and the script exits non-zero. `mkdir -p ./results/ranger` at `:16` is required — `tee` cannot create that directory and it is absent on a fresh checkout. The success message at `:72` is the final link of the `&&` chain rather than a standalone statement, because `set -e` does not abort on a mid-chain failure.

Logging convention: each `Rscript` step tees stdout+stderr to a `.log` file — the fitting steps into `results/ranger/`, the rest beside the script. The three `rmarkdown::render` steps (`:52`, `:56`, `:59`) still have **no** logging.

---

#### 4. `R_code/analysis/fit_tilefish_random_forest/batch_tile_RF_run.sh`

The tilefish counterpart to `batch_RF_run.sh`.

The smallest wrapper. Same comment/uncomment toggle style.

| # | Step | Lines | State |
|---|---|---|---|
| — | `00_tilefish_processing_wrapper.R` | `:13-15` | **OFF** (commented) |
| 1 | `fit_tilefish_classification.R` | `:18-20` | **ON** |

**Toggle detail:** the commented-out step at `:13-15` points to
`./R_code/data_extraction_processing/processing/tilefish/00_tilefish_processing_wrapper.R`.
The path resolves correctly, so the step will run if uncommented.

**Failure behaviour (`:2-3`).** `set -e` + `set -o pipefail`. The single live step is a standalone
statement rather than part of an `&&` list, so `set -e` applies to it directly: a failure exits before
the success message at `:22`. Verified with a stub `Rscript`. The commented-out data-prep step carries a
trailing `&&` so that uncommenting it chains correctly onto the fit step.

---

---

#### C1. `stata_code/analysis/00_analysis_wrapper.do`

Sets one global, then makes five sequential `do` calls with no other logic. Named `00_*_wrapper.do`, matching the naming convention of the confirmed wrappers.

| # | Script | Line |
|---|---|---|
| 1 | `$analysis_code/bsb_simple_hedonic.do` | `:4` |
| 2 | `$analysis_code/fmm_tries.do` | `:7` |
| 3 | `$analysis_code/bsb_size_classifications.do` | `:10` |
| 4 | `$analysis_code/bsb_size_classifications_V2.do` | `:13` |
| 5 | `$analysis_code/mlogit_prediction_summary.do` | `:17` |

**Toggle:** `global in_string 2026-03-16` at `:1`. This is the **only** configuration. Note the **hyphen** format, which differs from the commercial `.do` wrapper's underscore format — see [F-1](#f-1-in_string-points-each-pipeline-at-a-different-vintage).

There are no on/off toggles; all five run unconditionally.

Inline comments describe intent: `fmm_tries.do` is annotated *"I didn't really pursue this very much"* (`:6): step 2 is exploratory dead weight.

---

#### C2. `stata_code/data_extraction_processing/processing/commercial/00_commercial_processing_wrapper.do` — **RETIRED**

> **Status: RETIRED.** `:1` reads `/* this chain has been retired */`. The R wrapper (confirmed wrapper #1) is the live replacement. Documented here for reference — do not run it.


| # | Script | Line |
|---|---|---|
| 1 | `$processing_code/commercial/A01_make_landings_cleaned.do` | `:4` |
| 2 | `$processing_code/commercial/A02_make_daily_stats.do` | `:5` |
| 3 | `$processing_code/commercial/A03_make_dealer_stats.do` | `:7` |
| 4 | `$processing_code/commercial/A04_make_moving_average_prices.do` | `:8` |

**Toggle:** `global in_string 2026_05_01` at `:3` (**underscore** format).

Note it calls only `A01`–`A04`. There is **no Stata equivalent of `B01`/`B02`** — the ML data-prep stage exists only in R, which is part of why the Stata chain could not stand alone.

**Consequences worth knowing:**

- The four `stata_code/.../commercial/A0*.do` files are retired by extension. Nothing else calls them.
- `$processing_code` (`folder_setup_globals.do:19`) is now read **only** by retired code.
- The `$in_string` / `$vintage_string` inconsistency inside `A03_make_dealer_stats.do` (`:18` vs `:76`) is now a dead issue rather than a live defect.
- The **underscore** vintage format (`2026_05_01`) survives only here. Every live assignment uses hyphens. See [F-1](#f-1-in_string-points-each-pipeline-at-a-different-vintage).

---

#### C3. `writing/knit_ranger_results_in_loop.R`

Defines a render function and drives it from a `for` loop over a vector of model types (`:44-46`), rendering `writing/reading_ranger_results.Rmd` once per element. It orchestrates repeated execution of another file, which is wrapper-like, but it drives a single report rather than a pipeline.  This was used to puzzle over repeated model types.  But not anymore

| Element | Line | Value |
|---|---|---|
| `input_model_vec` | `:28` | `c("nocluster_Tsubset")` — **the active toggle** |
| `input_model_vec` (disabled) | `:26` | `c("standard","fiveclass","noc5class","nocluster","South_NOC","North_NOC")` — commented out |
| output dir | `:23` | `results/ranger/reports/`, created via `dir.create` |
| render target | `:34` | `writing/reading_ranger_results.Rmd`, `params = list(modeltype = input_model)` |

---

## Toggle Catalog

All on/off and configuration flags found, grouped by owner.

### Wrapper-level toggles

| Wrapper | Toggle | Default | Effect |
|---|---|---|---|
| `00_commercial_processing_wrapper.R` | `in_string` `:29` | `"2026-05-01"` | Input vintage from DataPull repo |
| | `vintage_string` `:30` | `Sys.Date()` | Output vintage (A0* only) |
| `00_tilefish_processing_wrapper.R` | `in_string` `:31` | `"2026-06-09"` | Input vintage from DataPull repo |
| | `vintage_string` `:32` | `Sys.Date()` | Output vintage (A0* only) |
| `batch_RF_run.sh` | comment/uncomment | 6 on, 5 off | See wrapper table above |
| `batch_tile_RF_run.sh` | comment/uncomment | 1 on, 1 off | See wrapper table above |
| `00_analysis_wrapper.do` (C1) | `global in_string` `:1` | `2026-03-16` | Input vintage, hyphen format |
| ~~`00_commercial_processing_wrapper.do` (C2)~~ **RETIRED** | `global in_string` `:3` | `2026_05_01` | Input vintage, underscore format. **Retired — not part of any live run.** |
| `knit_ranger_results_in_loop.R` (C3) | `input_model_vec` `:28` | `c("nocluster_Tsubset")` | Which model reports to render |

### Random-forest script toggles

These are set **per script**, not by the wrapper. `batch_RF_run.sh` does not pass any parameters — each `.R` file carries its own settings, so changing model type means editing several files.

| Script | `modeltype` | `search_type` | `testing_fraction` | Other |
|---|---|---|---|---|
| `tune_randomforest_nocluster.R` | `"nocluster"` `:66` | `"Advanced"` `:69` | `0.5` `:75` | `bayes_tune<-"FALSE"` `:79` |
| `train_randomforest_nocluster.R` | `"nocluster"` `:58` | `"Advanced"` `:61` | `1` `:70` | `bayes_tune<-"FALSE"` `:74`; `run_me = 0` `:267` |
| `variable_importance_randomforest_nocluster.R` | `"nocluster"` `:59` | `"Advanced"` `:62` | `1` `:71` | `bayes_tune<-"FALSE"` `:75` |
| `weighted_calibration.R` | `"nocluster"` `:62` | `"Advanced"` `:61` | — | — |
| `plot_ROC_curves.R` | `"nocluster"` `:23` | `"Advanced"` `:22` | — | — |
| `estimate_randomforest.R` | `"standard"` `:51` | `"Initial"` `:42` | `1.0` `:45` | — |
| `test_sampling.R` | `"nocluster"` `:24` | `"Initial"` `:17` | `1` `:21` | `bayes_tune<-"FALSE"` `:15` |
| `fit_tilefish_classification.R` | `"nocluster"` `:67` | `"Initial"` `:70` | `1.0` `:74` | — |

**What these do:**

- **`modeltype`** selects the file-naming patterns for input/output artifacts, via `helpers/modeltype_patterns.R`. Accepted values there are `"standard"`, `"nocluster"`, `"TESTnocluster"`; anything else hits `stop("Unknown modeltype")` at `modeltype_patterns.R:41`. The in-code comment at `tune_randomforest_nocluster.R:67` advertises `"fiveclass"` and `"noc5class"` as options, but **the helper does not implement them** — see [F-4](#f-4-modeltype-options-advertised-but-not-implemented).
- **`search_type`** takes `"Initial"`, `"Prototype"`, or `"Advanced"`. `"Prototype"` is special-cased at `modeltype_patterns.R:3-5`: it rewrites `modeltype` to `glue("TEST{modeltype}")`, redirecting all reads/writes to `TEST_`-prefixed files so a prototype run cannot clobber real results.
- **`testing_fraction`** is documented at `tune_randomforest_nocluster.R:74` as *"Only used with `search_type<-"Prototype"`"* — it subsets the data for fast code checks.
- **`bayes_tune`** switches between Bayesian and grid tuning (`tune_randomforest_nocluster.R:349`, `:382`). It is assigned the **string** `"FALSE"`, not the logical `FALSE`. R's `==` coerces here so the comparison works, but the typing is fragile.
- **`run_me`** (`train_randomforest_nocluster.R:267`) gates two mutually exclusive blocks at `:268` (`run_me == 1`) and `:293` (`run_me == 0`). Default `0`. **The downstream meaning of the two branches was not resolved by static reading** — the branches differ in how the final fit is produced. Flagged for review.

### Platform-detection toggles (not user-set)

Every RF script contains a platform block (e.g. `tune_randomforest_nocluster.R:85-120`) that sets `runClass` and then thread counts:

| `runClass` | `my.parallel.threads` | `my.ranger.multi.threads` |
|---|---|---|
| `Local` / `Windows` | 1 | 5 |
| `Container` / `DynamicContainer` | 2 | 11 (+ `sequential.threads` 23) |

`runClass` is assigned when `Sys.info()['sysname']` is `Linux` (`:87`) or `Windows` (`:97`) — the two platforms this project is developed on.

Under the container branch only, `helpers/background_logger.R` is sourced (`:117`). That helper shells out to `bash`, `top`, and `ps` (`background_logger.R:4-12`) and is Linux-only by construction.

### R Markdown parameter toggles

Six reports declare a `modeltype` param in YAML and read it via `params$modeltype`:

| Report | `params:` line | Default | Reads param at |
|---|---|---|---|
| `calibration_and_validation.Rmd` | `:15` | `nocluster` | `:53` |
| `out_of_sample_predictions.Rmd` | `:15` | `nocluster` | `:54` |
| `out_of_sample_predictions_StockAssess.Rmd` | `:15` | `nocluster` | `:56` |
| `predictions_heatmap.Rmd` | `:19` | `nocluster` | `:47` |
| `tuning_diagnostics.Rmd` | `:19` | `nocluster` | `:57` |
| `reading_ranger_results.Rmd` | `:19` | `South_region_NOC` | `:61` |

Note `reading_ranger_results.Rmd` defaults to a **different** model type than the other five, and does not use the shared helper (see [F-3](#f-3-duplicated-and-divergent-modeltype-dispatcher)).

### Plotting toggles

| Script | Toggle | Default |
|---|---|---|
| `market_category_price_plots.R` | `graph_disaggregate` `:21` | `TRUE` |
| | `graph_aggregate` `:22` | `TRUE` |
| `LAA_calculation_BSB.R` | `plotson` (function arg) | `TRUE` — `=FALSE` skips the plotting routine |

---

## Master Execution Sequence

Combined wrapped + inferred order. Segments are independent unless a dependency is stated.

### Stage 0 — Session setup (must precede everything)

```
[EXTERNAL PREREQUISITE — not in this repo]
0a. Stata's profile.do must define $mynetwork
    → folder_setup_globals.do:11 reads ${mynetwork} and everything else
      is built from it. If unset, every Stata path resolves relative to
      the current directory and the pipeline silently misbehaves.

0b. R: .Rprofile must define `nefscdb_con` for any StockEff/Oracle script
    → asserted by LAA_script.R:18 and LAA_investigation_script.R:17

[REPO — Stata sessions only]
0c. stata_code/project_logistics/folder_setup_globals.do
    Defines ~20 path globals; adds stata_code/ado to the adopath (:51);
    sets $today_date_string (:56) and $vintage_string (:57);
    then calls vintage_lookup_and_reset (:59).
    ** INTERACTIVE — blocks on a _request() prompt. See F-5. **

[REPO — R sessions, optional]
0d. R_code/project_logistics/R_paths_libraries.R
    Defines the R path objects and locates the Stata executable (:62-82).
    Not sourced by either R wrapper; used by r_oracle_connection.R:19.
```

### Stage 1 — Data extraction

```
[not used]
1a. R_code/data_extraction_processing/extraction/r_oracle_connection.R
1b. R_code/data_extraction_processing/extraction/dbi_extraction.R
1c. R_code/data_extraction_processing/extraction/FRED_extraction.R
      Requires FRED_API_KEY in .Renviron/.Rprofile (FRED_extraction.R:5-8).
```

### Stage 2 — Commercial processing

```
[WRAPPER— 00_commercial_processing_wrapper.R]  ← THE live path
2.  A01_make_landings_cleaned.R
      READS  (EXTERNAL) my_datapull/.../landings_all_{in_string}.Rds
      READS  (EXTERNAL) my_datapull/.../cams_gears_{in_string}.Rds
      READS  (EXTERNAL) my_datapull/.../deflators*.Rds
      WRITES data_folder/main/commercial/questionable_status_{vintage_string}.Rds  (:262)
      WRITES data_folder/main/commercial/landings_cleaned_{vintage_string}.Rds     (:278)
3.  A02_make_daily_stats.R      → camsid_specific_cleaned_, daily_ma_, state_ma_,
                                   stockarea_ma_, gear_ma_  (:274,322,357,390,423)
4.  A03_make_dealer_stats.R     → dlrid_historical_stats_, dlrid_lag_stats_ (:87,157)
5.  A04_make_moving_average_prices.R → grand_moving_average_prices_ (:275)
6.  B01_data_prep_ml.R
      RE-DERIVES vintage_string from disk (:66-69)  ← see F-2
      Sets out_data_string <- Sys.Date() (:73)
      READS the nine A0* outputs (:107-142)
      SOURCES BSB.Classification.Recipe.R (:559)
      WRITES BSB_original_combined_dataset{out_data_string}.{Rds,dta} (:506-507)
      WRITES BSB_unclassified_dataset{out_data_string}.{Rds,dta}      (:516-517)
      WRITES BSB_estimation_dataset{out_data_string}.{Rds,dta}        (:526-527)
7.  B02_handle_not_in_estimation_dataset.R
      RE-DERIVES vintage_string from BSB_original_combined_dataset* (:63-66)
      WRITES data_folder/predictions/excluded_from_estimation_dataset_{...}.Rds (:117)

[RETIRED — 00_commercial_processing_wrapper.do:1 "this chain has been retired"]
    DO NOT RUN. Superseded by the R chain above. Listed for historical
    reference so the .dta files already on disk can be traced to a producer.
2'. A01_make_landings_cleaned.do  → $data_main\commercial\landings_cleaned_${vintage_string}.dta (:205)
3'. A02_make_daily_stats.do       → daily_ma_, state_ma_, stockarea_ma_, gear_ma_ (:219-282)
4'. A03_make_dealer_stats.do      → dlrid_historical_stats_, dlrid_lag_stats_ (:65,109)
5'. A04_make_moving_average_prices.do → grand_moving_average_prices_ (:250)
    (No Stata B01/B02 equivalent ever existed — the ML data-prep stage is
     R-only, which is part of why this chain could not stand alone.)
```


### Stage 3 — Tilefish processing (parallel to Stage 2, independent)

```
[WRAPPER — 00_tilefish_processing_wrapper.R]
8.  A01_make_tilefish_landings_cleaned.R  (reads EXTERNAL DataPull; :23,141,225)
9.  A02_make_daily_tilefish_stats.R
10. A03_make_tilefish_dealer_stats.R
11. A04_make_tilefish_moving_average_prices.R
12. B01_data_prep_tilefish_ml.R  → tilefish_{original_combined,unclassified,estimation}_dataset*
13. B02_handle_not_in_tilefish_estimation_dataset.R
```

### Stage 4 — Random forest: tune → train → interpret

**Enabled in `batch_RF_run.sh**

```
[WRAPPER-CONFIRMED — batch_RF_run.sh:5-17]
14. tune_randomforest_nocluster.R
      READS  BSB_estimation_dataset{max vintage on disk}.Rds
      SOURCES modeltype_patterns.R (:72), BSB.Classification.Recipe.R (:258),
              BSB.Workflow.Setup.R (:261)
      WRITES results/ranger/{data_pattern}{today}.Rds
             results/ranger/{tuning_pattern}{today}.Rds
             results/ranger/{best_param_pattern}{today}.Rds
      NOTE: tuning_vintage <- Sys.Date() (:136) — "purposely set as today"
15. train_randomforest_nocluster.R    (consumes tuning output; run_me gate at :267)
16. variable_importance_randomforest_nocluster.R
```

### Stage 5 — Random forest post-processing (same batch, continues from Stage 4)

```
[WRAPPER — batch_RF_run.sh]
17. weighted_calibration.R        (:22-24)  → log beside script
      WRITES results/ranger/validation_preds{finalfit_vintage}.dta  (:238)
             ← haven::write_dta. AN R → STATA HANDOFF.
      WRITES results/ranger/aggregate_*_predictions_*.Rds (:832, :939)
18. writing/figure1.R             (:28-30)  → log beside script
--  writing/figure2.R             (:33-35)  OFF — "requires windows, run by hand"
19. render writing/predictions_heatmap.Rmd          (:38)
20. render writing/tuning_diagnostics.Rmd           (:42)
21. render writing/out_of_sample_predictions.Rmd    (:45)
      ** THIS IS THE PRODUCER OF THE LAA INPUTS. **
      WRITES data_folder/predictions/out_of_sample_predictions_YRS_{modeltype}{finalfit_vintage}.Rds  (:360)
      WRITES data_folder/predictions/ambitious_out_of_sample_predictions_YRS_{modeltype}{finalfit_vintage}.Rds  (:497)
      → Stage 7 (LAA/CAA/WHAM) must run AFTER this step. Verified dependency.
22. plot_ROC_curves.R             (:47-49)  → log beside script
--  render writing/Economic_informed_stock_assessments.Rmd  (:59) OFF, "TO DO"

[Wrapper— batch_tile_RF_run.sh]
23. fit_tilefish_classification.R (:9-11)
    Depends on Stage 3 output (tilefish_estimation_dataset*.Rds, :130-133).
    ALSO READS three CSVs that nothing in this repo writes — hand-placed:
      data_folder/main/tilefish/tilefish_lengths2007.csv  (:993)
      data_folder/main/tilefish/tilefish_keyfile.csv      (:995)
      data_folder/main/tilefish/tilefish_lengths2015.csv  (:997)
    WRITES data_folder/predictions/tilefish_out_of-sample_predictions_{vintage}.csv (:1364)
      ^ note the filename typo: "out_of-sample", not "out_of_sample".
    Unlike the BSB chain, this single script does tune + train + predict + plot
    (~1600 lines, ~20 ggsave calls to images/tilefish/exploratory/).
```

### Stage 6 — Stata 

```
[—00_analysis_wrapper.do]
24. bsb_simple_hedonic.do
      READS  ${data_main}\commercial\BSB_original_combined_dataset${in_string}.dta (:14)
             ← produced by R B01_data_prep_ml.R:507.  CROSS-LANGUAGE HANDOFF.
25. fmm_tries.do            ("I didn't really pursue this very much")
26. bsb_size_classifications.do
      WRITES $my_results/hedonic_table.md and 10 sibling .md/.tex tables (:229-357)
             ← consumed by writing/Appendix_Hedonic.Rmd:218.  CROSS-LANGUAGE HANDOFF.
      WRITES $data_main\commercial\mlogit_estimation_dataset_${vintage_string}.dta (:709)
27. bsb_size_classifications_V2.do
28. mlogit_prediction_summary.do
      READS  ${data_main}/commercial/mlogit_estimation_dataset_${vintage_string}.dta (:18)
             ← written by step 26. Same-session dependency via $vintage_string.
```

### Stage 7 — Landings-at-age / catch-at-age → WHAM

```
[INFERRED FROM DATA DEPENDENCY — not wrapper-controlled]
Each script's own header states "Hand-run. No wrapper calls this script."
(LAA_script.R:22-25)

29. LAA_script.R
      SOURCES get_intermediate_stockeff.R (:55), get_ages.R (:60),
              LAA_calculation_BSB.R (:61)  — in that order
      READS  out_of_sample_predictions_YRS_nocluster{vintage}.Rds
             ambitious_out_of_sample_predictions_YRS_nocluster{vintage}.Rds
             ← VERIFIED: written by writing/out_of_sample_predictions.Rmd:360,497
               (Stage 5 step 21). Vintage resolved by list.files()+max() glob.
      READS  StockEff via Oracle (needs nefscdb_con from .Rprofile)
      WRITES header :12-13 says "Outputs: NONE." — but the sourced
             LAA_calculation_BSB.R writes 5 PDFs to results/ when plotson=TRUE
             (:202, :277, :345, :385, :426), and LAA_script.R itself writes
             results/{CAA,WAA}_comparison_{UNC_only,all}.pdf (:402,:450,:514,:563).
      Purpose: verification/decomposition, builds five parallel LAA series.

30. CAA_calculation.R    (function definition)
      READS data_folder/intermediate/Comm.discards.at.age.RDATA via load() (:49)
            ← nothing in this repo writes this file. EXTERNAL BOUNDARY.

31. fit_BSB_WHAM/fit_BSB_WHAM.R
      SOURCES every .R in R_code/LAA_calculation/ whose name lacks "script"
              (:38-40, list.files + grepl filter + lapply(source))
      Opens its own Oracle connection (:54), interactively via
              rstudioapi::askForPassword() (:54-57)
      CALLS  get_intermediate_stockeff() (:65)
      READS  data_folder/assessment/BSB_2025MT_Input.rds (:43)
             data_folder/predictions/out_of_sample_predictions_YRS_*.Rds (:60-62)
             data_folder/assessment/BSB_2025MT_Fit.rds (:122)
      WRITES data_folder/assessment/BSB_Apportion_Fit.rds (:114)

[UNCLEAR / STANDALONE — LAA cluster, relationship not resolved]
- LAA_calculation.R              (monolithic version; exercised by LAA_test_script.R:56)
- LAA_calculation_BSB_old.R      (superseded; sourced only by test_refactor.R:24)
- LAA_test_script.R              (test harness)
- LAA_investigation_script.R     (sources get_intermediate_stockeff.R:69)
- test_refactor_script.R                (compares old vs new LAA implementations)
- get_ages.R, get_intermediate_stockeff.R, reallocate_market_categories.R
                                 (function definitions, no side effects)
```

### Stage 8 — Manuscript assembly

```
[UNCLEAR / MANUAL — the render call is commented out at batch_RF_run.sh:59]
32. render writing/Economic_informed_stock_assessments.Rmd
      SOURCES modeltype_patterns.R (:145), predict_byhand.R (:146)
      Sets modeltype<-"nocluster" (:138), search_type<-"Advanced" (:141)
      PULLS IN as child documents:
        - writing/build_summary_tables.Rmd   (:472)
        - writing/Appendix_Hedonic.Rmd       (:718)
        - writing/Appendix_DataSummaries.Rmd (:721)
        - writing/CRediT.Rmd                 (:881)
```

### Scripts that could not be placed

| Script | Why |
|---|---|
| `R_code/analysis/compare_biostat_rf_output.R` | Opens with `connection = db1` (`:4`) where `db1` is never defined in-repo; also uses `mkt.res` (`:16`) which is never created in this file. Requires pre-existing session state. Reads a **hard-coded** prediction file with an embedded `2026-03-16` vintage (`:15`). Writes to a **personal Downloads folder** (`:31`) — see F-9. |
| `R_code/analysis/market_category_aggregations.R` | Hard-codes `vintage_string<-"2025-07-28"` (`:36`). Reads `all_marketcategory_landings_*` from the **DataPull repo** (`:50`). Self-bootstrapping: writes `market_cat_aggregations_{vintage}.Rds` (`:82`), or modifies it if it already exists (`:61`). |
| `R_code/analysis/market_category_price_plots.R` | Hard-codes `vintage_string<-"2025-07-28"` (`:36`). Reads `market_cat_aggregations_*` (`:113`) → **runs after `market_category_aggregations.R`**. Writes 3 PNG families to `images/descriptive/`. |
| `R_code/analysis/market_category_bau_allocation.R` | Header (`:2`) says *"this is run AFTER the combined_dataset is created"* → after Stage 2 step 6. Hard-codes `data_vintage_string<-"2026-05-28"` (`:33`). Writes 2 PDFs to `images/background/`. Otherwise independent of the other two `market_category_*` scripts. |
| `R_code/analysis/fit_random_forest/estimate_randomforest.R` | Uses `modeltype<-"standard"` / `search_type<-"Initial"` — the only script on the `"standard"` path. Not referenced by `batch_RF_run.sh`.  The predecessor of the `tune`/`train` split. |
| `R_code/analysis/fit_random_forest/test_sampling.R` | a scratch/experiment file. No wrapper reference. |
| `writing/*.Rmd` (16 not listed above) | Reporting layer — see next section. |
| `R_code/analysis/fit_BSB_WHAM/compare_png/compare_model_figs.Rmd` | Figure-comparison report; no wrapper reference. |
| `R_code/.../tilefish/TilefishProject.Rmd` | Duplicates the tilefish wrapper's setup block (`:33-39`) but as a notebook. Parallel manual path to the confirmed wrapper. |

---

## Stata Global Macro Trace

Only globals used across more than one script are listed

Path globals — defined once in `folder_setup_globals.do`

```
Global: $mynetwork
Defined: NOT IN THIS REPO — expected from Stata's startup profile.do
Read by: folder_setup_globals.do (line 11)
Reassigned: NOT FOUND in repo
Note:    This is the root of the entire Stata path tree. EXTERNAL BOUNDARY.
```

```
Global: $my_megadir
Defined: folder_setup_globals.do, line 11  →  "${mynetwork}/PricesInStockAssessment"
Read by: folder_setup_globals.do (lines 12, 13)
Reassigned: NOT FOUND — appears stable
```

```
Global: $my_projdir
Defined: folder_setup_globals.do, line 12  →  "${my_megadir}/READ-SSB-Lee-BlackSeaBass"
Read by: folder_setup_globals.do (lines 16, 21, 26, 39, 40, 44, 48)
Reassigned: NOT FOUND — appears stable
```

```
Global: $my_datapull
Defined: folder_setup_globals.do, line 13  →  "${my_megadir}/READ-SSB-Lee-BSB-DataPull"
Read by: A01_make_landings_cleaned.do (lines 23, 67, 176)
Reassigned: NOT FOUND — appears stable
Note:    EXTERNAL BOUNDARY. Every file read through this global is produced
         outside this repository.
```

```
Global: $my_codedir      Defined: folder_setup_globals.do:16
Read by: folder_setup_globals.do (17, 20, 22)
Reassigned: NOT FOUND — appears stable

Global: $my_datadir      Defined: folder_setup_globals.do:26
Read by: folder_setup_globals.do (27, 29, 30, 32, 34)
Reassigned: NOT FOUND — appears stable

Global: $data_raw        Defined: folder_setup_globals.do:27
Read by: NOT FOUND — defined but never read in this repo
Reassigned: NOT FOUND — appears stable

Global: $processing_code Defined: folder_setup_globals.do:19
Read by: 00_commercial_processing_wrapper.do (4, 5, 7, 8) — retired chain only.
         No live consumer.
Reassigned: NOT FOUND — appears stable

Global: $analysis_code   Defined: folder_setup_globals.do:20
Read by: 00_analysis_wrapper.do (4, 7, 10, 13, 17)
Reassigned: NOT FOUND — appears stable

Global: $data_main       Defined: folder_setup_globals.do:32
Read by: all 5 analysis .do files; A01-A04 .do files;
         vintage_lookup_and_reset.ado:8; folder_vintage_lookup_and_reset.ado:15
Reassigned: NOT FOUND — appears stable

Global: $data_external   Defined: folder_setup_globals.do:30
Read by: extract_data_from_FRED.do (79, 112)
Reassigned: NOT FOUND

Global: $my_results      Defined: folder_setup_globals.do:40
Read by: all 5 analysis .do files (log using / collect export)
Reassigned: NOT FOUND — appears stable

Global: $intermediate_results   Defined: folder_setup_globals.do:39
Read by: NOT FOUND — defined but never read in this repo

Global: $my_images / $exploratory / $my_tables / $my_adopath / $R_code /
        $extract_process / $extraction_code / $data_internal / $data_intermediate
Defined: folder_setup_globals.do:44,45,48,22,21,17,18,29,34
Read by: $exploratory ← bsb_size_classifications_V2.do
         $my_adopath  ← folder_setup_globals.do:51 (adopath +)
         Others: NOT FOUND read anywhere in this repo.
```

### Vintage globals — the two that actually drive filenames

```
Global: $vintage_string          ← the OUTPUT vintage
Defined: folder_setup_globals.do, line 57  →  $today_date_string  (i.e. today, YYYY_MM_DD)
Read by: A01_make_landings_cleaned.do (205)
         A02_make_daily_stats.do (24, 193, 219, 239, 260, 282)
         A03_make_dealer_stats.do (65, 76, 109)
         A04_make_moving_average_prices.do (21, 250)
         bsb_size_classifications.do (709)
         mlogit_prediction_summary.do (18)
         extract_data_from_FRED.do (59, 79, 95, 112)
         vintage_lookup_and_reset.ado (39, 47, 50, 52)
         folder_vintage_lookup_and_reset.ado (44, 52, 55, 57)
REASSIGNED: vintage_lookup_and_reset.ado, line 51
            folder_vintage_lookup_and_reset.ado, line 56
            Both overwrite $vintage_string with interactive user input.
            The first of these fires from folder_setup_globals.do:59 during
            setup.
```

```
Global: $today_date_string
Defined: folder_setup_globals.do, line 56 (from c(current_date), format %td_CCYY_NN_DD)
Read by: folder_setup_globals.do (57)
Reassigned: NOT FOUND — appears stable
```

```
Global: $in_string               ← the INPUT vintage
Defined (LIVE):    00_analysis_wrapper.do, line 1  →  2026-03-16   (hyphens)
Defined (RETIRED): 00_commercial_processing_wrapper.do, line 3  →  2026_05_01
                   (underscores; retired chain)
Read by (LIVE):    bsb_simple_hedonic.do (1, 13, 14, 17)
                   bsb_size_classifications.do (2, 22, 27)
                   bsb_size_classifications_V2.do (1, 17, 22)
                   fmm_tries.do (1, 19, 20, 23)
                   mlogit_prediction_summary.do (1)
Read by (RETIRED): A01_make_landings_cleaned.do (23, 67, 176)
                   A03_make_dealer_stats.do (18)
REASSIGNED: Only one LIVE definition remains, so there is no live same-session
            clobbering. The risk returns only if the retired wrapper is run,
            which would overwrite $in_string with the underscore format for the
            remainder of the session. See F-1.
```

### Globals referenced but never defined in this repo

```
Global: $date
Defined: NOT FOUND ANYWHERE
Read by: appears ONLY inside comment blocks — A01_make_landings_cleaned.do (11-13),
         A02_make_daily_stats.do (9, 11-15), A03 (4), A04 (14, 16),
         bsb_simple_hedonic.do (6), bsb_size_classifications.do (8),
         bsb_size_classifications_V2.do (6), fmm_tries.do (7),
         mlogit_prediction_summary.do (6)
Assessment: NOT a live global. The header comments use "$date" as informal
            shorthand for whichever vintage applies; the executable code uses
            $vintage_string or $in_string. Documentation inconsistency only —
            no runtime effect.
```

---

## R Sourcing Order

R has no true globals; the equivalent mechanism here is **objects defined in one file and relied upon by another, via `source()` into the calling environment or via `child=` chunk inheritance.**

### Sourcing graph

```
00_commercial_processing_wrapper.R
├── helpers/gear_market_helpers.R                    :33
├── commercial/A01_make_landings_cleaned.R           :35
├── commercial/A02_make_daily_stats.R                :36
├── commercial/A03_make_dealer_stats.R               :37
├── commercial/A04_make_moving_average_prices.R      :38
├── commercial/B01_data_prep_ml.R                    :42
│   └── fit_random_forest/BSB.Classification.Recipe.R   :559
└── commercial/B02_handle_not_in_estimation_dataset.R   :45

00_tilefish_processing_wrapper.R
├── helpers/gear_market_helpers.R                    :35
└── tilefish/A01..A04, B01, B02                      :37,38,41,44,48,51

tune_randomforest_nocluster.R
├── helpers/modeltype_patterns.R                     :72
├── helpers/background_logger.R                      :117   [container branch only]
├── fit_random_forest/BSB.Classification.Recipe.R    :258
└── fit_random_forest/BSB.Workflow.Setup.R           :261

train_randomforest_nocluster.R
├── helpers/modeltype_patterns.R                     :65
├── helpers/predict_byhand.R                         :66
├── helpers/background_logger.R                      :106   [container branch only]
├── fit_random_forest/BSB.Classification.Recipe.R    :202
└── (BSB.Workflow.Setup.R                            :216   COMMENTED OUT)

variable_importance_randomforest_nocluster.R
├── helpers/modeltype_patterns.R                     :66
├── helpers/predict_byhand.R                         :67
├── helpers/background_logger.R                      :107
└── (BSB.Classification.Recipe.R :201, BSB.Workflow.Setup.R :208  BOTH COMMENTED OUT)

weighted_calibration.R  →  modeltype_patterns.R :110, predict_byhand.R :111
plot_ROC_curves.R       →  modeltype_patterns.R :71,  predict_byhand.R :72
estimate_randomforest.R →  BSB.Classification.Recipe.R :238, BSB.Workflow.Setup.R :239

fit_tilefish_classification.R
├── helpers/background_logger.R                      :109
├── fit_tilefish_random_forest/Tilefish.Classification.Recipe.R  :230
└── fit_tilefish_random_forest/Tilefish.Workflow.Setup.R         :233

LAA_script.R
├── LAA_calculation/get_intermediate_stockeff.R      :55
├── LAA_calculation/get_ages.R                       :60
└── LAA_calculation/LAA_calculation_BSB.R            :61
    └── LAA_calculation/get_intermediate_stockeff.R  :43   (sourced again)

LAA_investigation_script.R
├── LAA_calculation/get_intermediate_stockeff.R      :69
├── LAA_calculation/reallocate_market_categories.R   :75
└── LAA_calculation/get_ages.R                       :76

LAA_test_script.R  →  LAA_calculation/LAA_calculation.R :56
test_refactor.R    →  LAA_calculation_BSB_old.R :24, get_intermediate_stockeff.R :35,
                      LAA_calculation_BSB.R :36

r_oracle_connection.R  →  project_logistics/R_paths_libraries.R :19

writing/*.Rmd  →  modeltype_patterns.R + predict_byhand.R
                  (calibration_and_validation :128-129,
                   Economic_informed_stock_assessments :145-146,
                   out_of_sample_predictions :127-128,
                   out_of_sample_predictions_StockAssess :132-133,
                   predictions_heatmap :121-122,
                   tuning_diagnostics :130-131)
```

### R equivalents of globals — objects that cross file boundaries

```
Object: modeltype, search_type
Defined: in each RF driver script, before sourcing the helper (see Toggle Catalog)
Read by: helpers/modeltype_patterns.R (lines 3, 9, 18, 29)
Mechanism: source() evaluates in the caller's environment, so the helper reads
           variables it never receives as arguments. This is an IMPLICIT CONTRACT
           — modeltype_patterns.R cannot run standalone; it errors at :41 if
           `modeltype` is absent or unrecognised.
Reassigned: YES — modeltype_patterns.R:4 rewrites `modeltype` itself when
           search_type=="Prototype", prefixing it with "TEST". A caller that
           inspects `modeltype` after sourcing sees a different value than it set.
           Needs review.
```

```
Objects: data_pattern, tuning_pattern, final_pattern, vi_pattern,
         best_param_pattern, prepped_recipe, calib_data_pattern
Defined: helpers/modeltype_patterns.R :10-16 / :19-25 / :30-36
Read by: every RF driver and every writing/*.Rmd that sources the helper
Mechanism: written into the caller's environment. The R analogue of Stata's
           global-macro handoff.
```

```
Object: vintage_string
Defined (R): 00_commercial_processing_wrapper.R:30  →  Sys.Date()
             00_tilefish_processing_wrapper.R:32    →  Sys.Date()
REASSIGNED by DISK SCAN in 19 downstream files (12 .R, 7 .Rmd), all with
            the same idiom:
             list.files(<dir>, pattern=glob2rx("<stem>*Rds")) |> gsub |> max()
  B01_data_prep_ml.R:66-69                      (stem: landings_cleaned_)
  B02_handle_not_in_estimation_dataset.R:63-66  (stem: BSB_original_combined_dataset)
  B01_data_prep_tilefish_ml.R:21-24             (stem: tilefish_landings_cleaned_)
  B02_handle_not_in_tilefish_estimation_dataset.R:24-27
  tune_randomforest_nocluster.R:130-133         (stem: BSB_estimation_dataset)
  train_randomforest_nocluster.R:121-123
  variable_importance_randomforest_nocluster.R:122-124
  weighted_calibration.R:151
  plot_ROC_curves.R:112
  test_sampling.R:111-114
  estimate_randomforest.R:125-128
  fit_tilefish_classification.R:130-133         (stem: tilefish_estimation_dataset)
  writing/{estimate_multinomial, out_of_sample_predictions,
           out_of_sample_predictions_StockAssess, predictions_heatmap,
           reading_ranger_results, tuning_diagnostics, calibration_and_validation}.Rmd
HARD-CODED (does not scan):
  market_category_aggregations.R:36   →  "2025-07-28"
  market_category_price_plots.R:36    →  "2025-07-28"
  writing/figure1.R:39-40             →  derived from a `dataset_name` variable
Assessment: This is a fundamentally different contract from Stata's. See F-2.
```

```
Object: out_data_string
Defined: B01_data_prep_ml.R:73  →  Sys.Date()
         B01_data_prep_tilefish_ml.R:28  →  Sys.Date()
Read by: the same file only (:506-527 / :343-361)
Effect:  B01 READS files stamped with the scanned `vintage_string` but WRITES
         files stamped with today's date. If A0* ran on a previous day, the
         input and output vintages of B01 differ. This is deliberate-looking
         but is worth confirming.
```

```
Object: tuning_vintage
Defined: tune_randomforest_nocluster.R:136  →  as.character(Sys.Date())
Comment at :135 states "Tuning vintage is purposely set as 'today'".
Read by: :139-141 to name the data-split, tuning, and best-param output files.
Effect:  Every tuning run creates a NEW dated artifact set rather than
         overwriting. Downstream scripts then pick these up by max() scan.
```

```
Object: my_datapull / mega_dir / data_pull_dir
Defined: 00_commercial_processing_wrapper.R:25-26, 00_tilefish_processing_wrapper.R:25-26
         (my_datapull <- file.path(dirname(here()), "READ-SSB-Lee-BSB-DataPull"))
         B01_data_prep_ml.R:59-60, market_category_aggregations.R:28-29,
         market_category_price_plots.R:30-31   (as mega_dir / data_pull_dir)
Assessment: EXTERNAL BOUNDARY. Two different names for the same concept, each
         re-derived locally. All of them assume the DataPull repo is a SIBLING
         DIRECTORY of this repo. Nothing validates that assumption.
```

```
Object: data_vintage_string
Defined: calibration_and_validation.Rmd:150-153  (scans results/ranger/)
READ BUT NEVER DEFINED IN: writing/Appendix_Hedonic.Rmd:18
Mechanism: Appendix_Hedonic.Rmd is a CHILD document, pulled in by
         Economic_informed_stock_assessments.Rmd:718. It inherits the parent's
         environment. Run standalone it fails with "object not found".
Assessment: This is the R analogue of Stata's cross-script global-scope leakage,
         and it carries the same risk: the child's behaviour depends on what the
         parent happened to set.
```

```
Objects: nefscdb_con, db1, connection, mkt.res
Defined: NOT IN THIS REPO
Read by: LAA_script.R (header :18 asserts nefscdb_con must exist via .Rprofile)
         LAA_investigation_script.R:121  (connection <- eval(nefscdb_con))
         compare_biostat_rf_output.R:4   (connection = db1)  and :16 (mkt.res)
Assessment: EXTERNAL BOUNDARY — session state supplied by the developer's
         .Rprofile. compare_biostat_rf_output.R additionally depends on `mkt.res`,
         which is a return value of get_intermediate_stockeff(); the script does
         not create it, so it only runs after something else has populated the
         session.
```

```
conflicted::conflicts_prefer() is set in both R wrappers (:15-20 / :15-20) and
in several helpers. These are session-wide and will affect any script sourced
afterwards.
```

### `writing/` R Markdown inventory (inputs only)

Per scope, these are catalogued but **not** placed in a relative order.

| Report | Primary inputs | Notes |
|---|---|---|
| `Economic_informed_stock_assessments.Rmd` | ranger results; 4 child docs | The manuscript. Render is commented out in `batch_RF_run.sh:59`. |
| `build_summary_tables.Rmd` | `data_split`, `oos_data` from parent env | **Child** of the manuscript (`:472`). No YAML — cannot run standalone. |
| `Appendix_Hedonic.Rmd` | `BSB_original_combined_dataset{data_vintage_string}.Rds`; `results/hedonic_table.md` | **Child** (`:718`). Consumes a **Stata-generated** table via `child=` at `:218`. |
| `Appendix_DataSummaries.Rmd` | tables from parent env | **Child** (`:721`). |
| `CRediT.Rmd` | none | **Child** (`:881`). Prose only. |
| `predictions_heatmap.Rmd` | `BSB_estimation_dataset*`, ranger results | Rendered by `batch_RF_run.sh:38`. |
| `tuning_diagnostics.Rmd` | ranger tuning results | Rendered by `batch_RF_run.sh:42`. Fold-level ROC. |
| `out_of_sample_predictions.Rmd` | `BSB_estimation_dataset*`, ranger results | Rendered by `batch_RF_run.sh:45`. Produces the prediction files LAA consumes. |
| `out_of_sample_predictions_StockAssess.Rmd` | same | Stock-assessment variant. Not in any wrapper. |
| `calibration_and_validation.Rmd` | `results/ranger/{data_pattern}*`, `BSB_unclassified_dataset*` | Not in any wrapper. |
| `reading_ranger_results.Rmd` | ranger data/tuning/final results | Driven by candidate wrapper C3. **Own inline dispatcher** — see F-3. |
| `estimate_multinomial.Rmd` | `BSB_estimation_dataset*` | Not in any wrapper. |
| `summary_tables.Rmd` | estimation dataset | Not in any wrapper. |
| `investigate_fit.Rmd` | narrative; `eval=FALSE` chunks | Lab notebook, not a data product. |
| `mnl_logit.Rmd` | narrative/math | Methods prose. |
| `strategic_interactions.Rmd` | — | References `BSB_history.Rmd` and `BSB_economic_background.Rmd` at `:172`; **neither file exists**. Guarded by `eval=FALSE`. |
| `HakeandTileExploratoryAnalysis.Rmd` | DataPull repo; `in_string <- "2026-06-09"` at `:301` | Exploratory. Comments at `:616-617` reference helper functions "loaded from source()" but the file has **no `source()` call**. |
| `Appendix_*`/`CRediT` | see above | |
| `R_code/.../TilefishProject.Rmd` | duplicates tilefish wrapper setup `:33-39` | Notebook mirror of the tilefish wrapper. |
| `fit_BSB_WHAM/compare_png/compare_model_figs.Rmd` | WHAM output PNGs | Figure comparison. |

---

## Known Issues

### F-1: `$in_string` points each pipeline at a different vintage

| Where | Line | Value |
|---|---|---|
| `00_analysis_wrapper.do` | `:1` | `2026-03-16` |
| `00_commercial_processing_wrapper.R` | `:29` | `"2026-05-01"` |
| `00_tilefish_processing_wrapper.R` | `:31` | `"2026-06-09"` |

All three use the hyphenated `YYYY-MM-DD` form, so filenames are consistent. The values differ because each pipeline points at an independently-refreshed DataPull vintage. The practical consequence is that the Stata analysis chain reads a **March** combined dataset while the R commercial chain was built from a **May** pull.

The retired `00_commercial_processing_wrapper.do` sets `$in_string` at `:3` using an underscore form (`2026_05_01`). Running it would leave that value, and that format, in effect for the rest of the Stata session.

Needs review.

### F-2: R `vintage_string` is overwritten mid-wrapper

`00_commercial_processing_wrapper.R:30` sets `vintage_string <- Sys.Date()`. That value governs `A01`–`A04`. Then `B01_data_prep_ml.R:66-69` discards it and re-derives `vintage_string` by scanning `data_folder/main/commercial/` for `landings_cleaned_*.Rds` and taking `max()`.

In a same-day run these agree. They diverge if:

- `A01`–`A04` ran on a different day than `B01`;
- an older `landings_cleaned_*.Rds` sorts lexicographically higher than the new one;
- the folder contains files from an unrelated run.

`max()` on a character vector is a lexicographic comparison. It happens to be correct for `YYYY-MM-DD`, but it is not a date comparison, and on an empty vector it returns `-Inf` with a warning rather than failing loudly.

### F-3: Duplicated and divergent `modeltype` dispatcher

`helpers/modeltype_patterns.R` handles three model types (`standard`, `nocluster`, `TESTnocluster`) and defines seven pattern variables.

`writing/reading_ranger_results.Rmd:104-128+` contains its own inline dispatcher that handles more types (`5class`, `5_NOC_class`, `South`, `North`, `Tsubset` variants) but defines only three variables (`data_pattern`, `tuning_pattern`, `final_pattern`). The two are not kept in sync — a model type added to one will not exist in the other.

### F-4: `modeltype` options advertised but not implemented

The comment at `tune_randomforest_nocluster.R:67` reads:

```r
# OR "nocluster", or "fiveclass", or "noc5class" OR "standard"
```

`modeltype_patterns.R` implements neither `"fiveclass"` nor `"noc5class"` — setting either triggers `stop("Unknown modeltype")` at `:41`. Candidate wrapper C3 (`knit_ranger_results_in_loop.R:28`) drives `modeltype = "nocluster_Tsubset"`, which the shared helper also does not implement; that works only because `reading_ranger_results.Rmd` uses its own dispatcher (F-3).

### F-5: Stata setup is interactive and will block a non-interactive run

`folder_setup_globals.do:59` calls `vintage_lookup_and_reset`. That program (`vintage_lookup_and_reset.ado:43`) issues a `_request(_vintage_string_bypass)` prompt and waits for input. Running `folder_setup_globals.do` in batch mode (`stata -b do ...`) will hang, or consume the next line of the file as the response.

Both `.ado` files behave this way. `folder_vintage_lookup_and_reset.ado` is a near-identical copy that scans subdirectories instead of files, and is never called anywhere in this repo.

### F-9: Hard-coded personal paths and pinned vintages

Paths that will not resolve for another developer:

| Location | Path | Kind |
|---|---|---|
| `compare_biostat_rf_output.R:31` | `C:/Users/emily.liljestrand/Downloads/compare_BIOSTAT_RF.csv` | write target |
| `fit_BSB_WHAM.R:26,32` | `C:/Users/emily.liljestrand/AppData/Local/R/win-library/...` (for `wham`) | library path |

Separately, several scripts pin a vintage as a literal rather than deriving it:

| Script | Line | Pinned vintage |
|---|---|---|
| `market_category_aggregations.R` | `:36` | `"2025-07-28"` |
| `market_category_price_plots.R` | `:36` | `"2025-07-28"` |
| `market_category_bau_allocation.R` | `:33` | `"2026-05-28"` |
| `compare_biostat_rf_output.R` | `:15` | `...2026-03-16.RDS` |
| `test_refactor.R` | `:13` | `...2026-06-15.rds` |
| `HakeandTileExploratoryAnalysis.Rmd` | `:29-30` | `2026-06-08`, `2026-06-09` |

These will silently read stale data, or fail, once those files age out.

---

## To clarify


1. **Vintage skew (F-1).** Whether the Stata analysis chain should be reading a March dataset while the R commercial chain was built from a May pull. This is "fine" but should be moved to the May data pull and tables rebuilt.
2. **`estimate_randomforest.R` and `test_sampling.R`.** These predate the tune/train split and Min-Yang is pretty sure these are retired.
3. **The `LAA_calculation/` cluster.** Which of `LAA_calculation.R`, `LAA_calculation_BSB.R`, and `LAA_calculation_BSB_old.R` is canonical. This is still indevelopment.
4. **`out_of_sample_predictions_StockAssess.Rmd`.** Its outputs carry an `SA_` prefix and are therefore not picked up by the LAA scripts' unprefixed globs — a separate branch, or an oversight.  Min-Yang thinks this is retired.

