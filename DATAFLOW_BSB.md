# BSB: Data Flow & Execution Order

Companion document: [`README.md`](README.md) (orientation + onboarding).

---

## Executive Summary

The repository contains **six wrapper scripts**: two R `source()` wrappers, two bash `Rscript` wrappers, one live Stata `do` wrapper, and one Stata `do` wrapper that has been **retired in place**. A seventh script, `writing/knit_ranger_results_in_loop.R`, drives one report in a loop and is documented alongside them. Across the repo there are **54 `.R` files, 12 `.do` files, 18 `.Rmd` files, 2 `.sh` files, and 2 `.ado` programs** — 88 scripts in all. Roughly **30 are reachable from a wrapper** (23 invoked directly, plus 7 more pulled in by `source()`). The remainder are hand-run.


**Ten open issues are catalogued below** (F-1 … F-10), ranging from a vintage skew between the R and Stata halves of the pipeline to a script that sources itself.

Three structural facts dominate everything below and should be read before the detail sections:

1. **The R `A01`–`A04` chain is the live commercial-processing path; the Stata `A01`–`A04` chain is retired**, marked as such at `00_commercial_processing_wrapper.do:1`. Both write the same file stems, differing only in extension (`.dta` vs `.Rds`); only the `.Rds` side is current. The retirement covers commercial *processing* only — the Stata *analysis* chain (`00_analysis_wrapper.do` and its five do-files) is live, and consumes `.dta` files written by `B01_data_prep_ml.R:507`.
2. **Stata passes vintages by explicit global macro; R passes them by scanning the disk.** Every downstream R script re-derives its vintage with `list.files(...)` then `max()`. This means the R wrapper's `vintage_string` assignment does **not** propagate past the `A0*` scripts — `B01` silently overwrites it. These are genuinely different mechanisms and are documented separately.
3. **`$in_string` is assigned a different value by each live wrapper**, pointing each pipeline at a different DataPull vintage (`2026-03-16` for the Stata analysis chain, `2026-05-01` commercial, `2026-06-09` tilefish). All live assignments share the hyphenated format; the odd underscore form survives only in the retired wrapper. Flagged, not resolved — see [F-1](#f-1-in_string-points-each-pipeline-at-a-different-vintage).

**Method note.** Everything below comes from reading the code, not from running it. Where a claim would require execution to confirm, it says so.

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

The header comment at `:2-3` says `00_commercial_processing_wrapper.R` / "R equivalent of `00_commercial_processing_wrapper.do`" — accurate here.

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

A bash script that invokes `Rscript` and `rmarkdown::render` from the **project root**. Unlike the R wrappers, **its toggles are comment/uncomment, not variables.** Nine of eleven steps are currently enabled.

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
| — | render `writing/Economic_informed_stock_assessments.Rmd` → pdf | `:82` | **OFF** — under a `Next steps (deliberately not in pipeline)` header at `:77-78` |

**This is the full end-to-end chain**: the three model-producing steps (tune → train → variable importance) feed the calibration, figure, report, and ROC steps that consume them. Nine steps run, joined by `&&`.

**Failure behaviour (`:2-3`, `:16`, `:66-72`).** `set -e` plus `set -o pipefail`, and the nine steps are `&&`-chained, so a failed step halts the batch and the script exits non-zero. `mkdir -p ./results/ranger` at `:16` is required — `tee` cannot create that directory and it is absent on a fresh checkout. The success message at `:72` is the final link of the `&&` chain rather than a standalone statement, because `set -e` does not abort on a mid-chain failure. The comment block at `:66-71` spells out that reasoning in the file itself.

Logging convention: each `Rscript` step tees stdout and stderr to a `.log` file — the fitting steps into `results/ranger/`, the rest beside the script. The three `rmarkdown::render` steps (`:52`, `:56`, `:59`) have **no** logging.

---

#### 4. `R_code/analysis/fit_tilefish_random_forest/batch_tile_RF_run.sh`

The tilefish counterpart to `batch_RF_run.sh`, and the smallest wrapper. Same comment/uncomment toggle style.

| # | Step | Lines | State |
|---|---|---|---|
| — | `00_tilefish_processing_wrapper.R` | `:11-13` | **OFF** (commented) |
| 1 | `fit_tilefish_classification.R` | `:16-18` | **ON** |

**Toggle detail:** the commented-out step at `:11-13` points to
`./R_code/data_extraction_processing/processing/tilefish/00_tilefish_processing_wrapper.R`.
The path resolves correctly relative to the project root, so the step should run if uncommented.

**Failure behaviour (`:2-3`).** `set -e` plus `set -o pipefail`. The single live step is a standalone
statement rather than part of an `&&` list, so `set -e` applies to it directly and a failure should exit
before the success message at `:20`. The commented-out data-prep step carries a trailing `&&` at `:13`
so that uncommenting it chains correctly onto the fit step.

---

#### 5. `stata_code/analysis/00_analysis_wrapper.do`

Sets one global, then makes five sequential `do` calls with no other logic. This is the live Stata chain.

| # | Script | Line |
|---|---|---|
| 1 | `$analysis_code/bsb_simple_hedonic.do` | `:4` |
| 2 | `$analysis_code/fmm_tries.do` | `:7` |
| 3 | `$analysis_code/bsb_size_classifications.do` | `:10` |
| 4 | `$analysis_code/bsb_size_classifications_V2.do` | `:13` |
| 5 | `$analysis_code/mlogit_prediction_summary.do` | `:17` |

**Toggle:** `global in_string 2026-03-16` at `:1`. This is the **only** configuration. Note the **hyphen** format, which differs from the retired commercial `.do` wrapper's underscore format — see [F-1](#f-1-in_string-points-each-pipeline-at-a-different-vintage).

There are no on/off toggles; all five run unconditionally.

Inline comments describe intent: `fmm_tries.do` is annotated *"I didn't really pursue this very much"* (`:6`), so step 2 is exploratory dead weight.

---

#### 6. `stata_code/data_extraction_processing/processing/commercial/00_commercial_processing_wrapper.do` — **RETIRED**

> **Status: RETIRED.** `:1` reads `/* this chain has been retired */`, and the entire body sits inside a `/* ... */` block spanning `:2-10`. Wrapper #1 (the R version) is the live replacement. Documented here for reference — do not run it.

| # | Script | Line |
|---|---|---|
| 1 | `$processing_code/commercial/A01_make_landings_cleaned.do` | `:4` |
| 2 | `$processing_code/commercial/A02_make_daily_stats.do` | `:5` |
| 3 | `$processing_code/commercial/A03_make_dealer_stats.do` | `:7` |
| 4 | `$processing_code/commercial/A04_make_moving_average_prices.do` | `:8` |

**Toggle:** `global in_string 2026_05_01` at `:3` (**underscore** format). Because the whole block is commented out, that assignment does not execute as the file currently stands.

Note it calls only `A01`–`A04`. There is **no Stata equivalent of `B01`/`B02`** — the ML data-prep stage exists only in R, which is part of why the Stata chain could not stand alone.

**Consequences worth knowing:**

- The four `stata_code/.../commercial/A0*.do` files are retired by extension. Nothing else calls them.
- `$processing_code` (`folder_setup_globals.do:19`) is now referenced **only** by this retired file, and only inside its comment block.
- The `$in_string` / `$vintage_string` inconsistency inside `A03_make_dealer_stats.do` (`:18` reads `landings_cleaned_${in_string}`, `:76` reads `landings_cleaned_${vintage_string}`) is now a dead issue rather than a live defect.
- The **underscore** vintage format (`2026_05_01`) survives only here. Every live assignment uses hyphens. See [F-1](#f-1-in_string-points-each-pipeline-at-a-different-vintage).

---

#### 7. `writing/knit_ranger_results_in_loop.R` — report driver, not a pipeline stage

Defines a render function and drives it from a `for` loop over a vector of model types (`:44-46`), rendering `writing/reading_ranger_results.Rmd` once per element. It orchestrates repeated execution of another file, which is wrapper-like, but it drives a single report rather than a pipeline. It was used to compare repeated model types and is not part of current runs.

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
| `batch_RF_run.sh` | comment/uncomment | **9 on, 2 off** | See wrapper table above |
| `batch_tile_RF_run.sh` | comment/uncomment | **1 on, 1 off** | See wrapper table above |
| `00_analysis_wrapper.do` | `global in_string` `:1` | `2026-03-16` | Input vintage, hyphen format |
| ~~`00_commercial_processing_wrapper.do`~~ **RETIRED** | `global in_string` `:3` | `2026_05_01` | Input vintage, underscore format. Inside the comment block — does not execute. |
| `knit_ranger_results_in_loop.R` | `input_model_vec` `:28` | `c("nocluster_Tsubset")` | Which model reports to render |

### Random-forest script toggles

These are set **per script**, not by the wrapper. `batch_RF_run.sh` does not pass any parameters — each `.R` file carries its own settings, so changing model type means editing several files.

| Script | `modeltype` | `search_type` | `testing_fraction` | Other |
|---|---|---|---|---|
| `tune_randomforest_nocluster.R` | `"nocluster"` `:66` | `"Advanced"` `:69` | `0.5` `:75` | `bayes_tune<-"FALSE"` `:79` |
| `train_randomforest_nocluster.R` | `"nocluster"` `:58` | `"Advanced"` `:61` | `1` `:70` | `bayes_tune<-"FALSE"` `:74`; **`fit_model = 1`** `:272` |
| `variable_importance_randomforest_nocluster.R` | `"nocluster"` `:59` | `"Advanced"` `:62` | `1` `:71` | `bayes_tune<-"FALSE"` `:75` |
| `weighted_calibration.R` | `"nocluster"` `:62` | `"Advanced"` `:61` | — | — |
| `plot_ROC_curves.R` | `"nocluster"` `:23` | `"Advanced"` `:22` | — | — |
| `estimate_randomforest.R` | `"standard"` `:51` | `"Initial"` `:42` | `1.0` `:45` | — |
| `test_sampling.R` | `"nocluster"` `:24` | `"Initial"` `:17` | `1` `:21` | `bayes_tune<-"FALSE"` `:15` |
| `fit_tilefish_classification.R` | `"nocluster"` `:67` | `"Initial"` `:70` | `1.0` `:74` | — |

**What these do:**

- **`modeltype`** selects the file-naming patterns for input/output artifacts, via `helpers/modeltype_patterns.R`. Accepted values there are `"standard"` (`:9`), `"nocluster"` (`:18`), and `"TESTnocluster"` (`:29`); anything else hits `stop("Unknown modeltype")` at `modeltype_patterns.R:41`. The in-code comment at `tune_randomforest_nocluster.R:67` advertises `"fiveclass"` and `"noc5class"` as options, but **the shared helper does not implement them** — see [F-4](#f-4-modeltype-options-advertised-but-not-implemented).
- **`search_type`** takes `"Initial"`, `"Prototype"`, or `"Advanced"`. `"Prototype"` is special-cased at `modeltype_patterns.R:3-5`: it rewrites `modeltype` to `glue("TEST{modeltype}")`, redirecting all reads and writes to `TEST_`-prefixed files so a prototype run cannot clobber real results.
- **`testing_fraction`** is documented at `tune_randomforest_nocluster.R:74` as *"Only used with `search_type<-"Prototype"`"* — it subsets the data for fast code checks.
- **`bayes_tune`** switches between Bayesian and grid tuning (`tune_randomforest_nocluster.R:349`, `:382`). It is assigned the **string** `"FALSE"`, not the logical `FALSE`. R coerces the logical to character in `"FALSE" == FALSE`, so the comparison evaluates as intended, but the typing is fragile.
- **`fit_model`** (`train_randomforest_nocluster.R:272`, default **`1`**) gates two mutually exclusive blocks at `:275` (`fit_model == 1`) and `:300` (`fit_model == 0`). The file documents the intent at `:269-271`: `fit_model = 1` fits the final `ranger` model from scratch and writes it to `results/ranger/`; `fit_model = 0` is a short-cut that reads the previously fitted model and the prepped recipe back off disk, so the augment and calibration work further down the script can be re-run without paying for a re-fit.

### Platform-detection toggles (not user-set)

Every RF script contains a platform block (e.g. `tune_randomforest_nocluster.R:85-120`) that sets `runClass` and then thread counts:

| `runClass` | `my.parallel.threads` | `my.ranger.multi.threads` |
|---|---|---|
| `Local` / `Windows` | 1 | 5 |
| `Container` / `DynamicContainer` | 2 | 11 (plus `my.ranger.sequential.threads` 23) |

`runClass` is assigned when `Sys.info()['sysname']` is `Linux` (`:87`, split further into `Container` / `DynamicContainer` on a `PREEMPT_DYNAMIC` test) or `Windows` (`:97`) — the two platforms this project is developed on. Note that `'Local'` appears in the `%in%` test at `:102` but is never assigned anywhere, so on an unrecognised platform `runClass` does not exist and the block errors.

Under the container branch only, `helpers/background_logger.R` is sourced (`:117`), preceded by a `pkill` of any prior logger. That helper shells out to `bash`, `top`, and `ps` (`background_logger.R:4-12`) and is Linux-only by construction.

### R Markdown parameter toggles

Five reports declare a `modeltype` param in YAML and read it via `params$modeltype`:

| Report | `modeltype:` key | Default | Reads param at |
|---|---|---|---|
| `calibration_and_validation.Rmd` | `:16` | `nocluster` | `:53` |
| `out_of_sample_predictions.Rmd` | `:16` | `nocluster` | `:54` |
| `predictions_heatmap.Rmd` | `:20` | `nocluster` | `:47` |
| `tuning_diagnostics.Rmd` | `:20` | `nocluster` | `:57` |
| `reading_ranger_results.Rmd` | `:20` | `South_region_NOC` | `:61` |

Note `reading_ranger_results.Rmd` defaults to a **different** model type than the other four, and does not use the shared helper (see [F-3](#f-3-duplicated-and-divergent-modeltype-dispatcher)).

### Plotting toggles

| Script | Toggle | Default |
|---|---|---|
| `market_category_price_plots.R` | `graph_disaggregate` `:21` | `TRUE` |
| | `graph_aggregate` `:22` | `TRUE` |
| `LAA_calculation_BSB.R` | `plotson` (function arg, `:52`) | `TRUE` — `=FALSE` skips the five plotting blocks guarded at `:172, :247, :315, :355, :395` |

---

## Master Execution Sequence

Segments are independent unless a dependency is stated.

### Stage 0 — Session setup (must precede everything)

```
[EXTERNAL PREREQUISITE — not in this repo]
0a. Stata's profile.do must define $mynetwork
    → folder_setup_globals.do:11 reads ${mynetwork} and everything else
      is built from it. If unset, every Stata path resolves relative to
      the current directory and the pipeline silently misbehaves.

0b. R: .Rprofile must define `nefscdb_con` for any StockEff/Oracle script
    → asserted in the headers of LAA_script.R:16 and LAA_investigation_script.R:16

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
[not used in the current pipeline]
1a. R_code/data_extraction_processing/extraction/r_oracle_connection.R
1b. R_code/data_extraction_processing/extraction/dbi_extraction.R
1c. R_code/data_extraction_processing/extraction/FRED_extraction.R
      Requires FRED_API_KEY in .Renviron/.Rprofile (checked at FRED_extraction.R:8).

NOTE: the Stata-side extraction folder
      (stata_code/data_extraction_processing/extraction/) is now EMPTY.
      extract_data_from_FRED.do has been removed from this repo; FRED
      extraction lives in the DataPull repo.
```

### Stage 2 — Commercial processing

```
[WRAPPER — 00_commercial_processing_wrapper.R]  ← THE live path
2.  A01_make_landings_cleaned.R
      READS  (EXTERNAL) my_datapull/.../landings_all_{in_string}.Rds
      READS  (EXTERNAL) my_datapull/.../cams_gears_{in_string}.Rds
      READS  (EXTERNAL) my_datapull/.../deflators*.Rds
      WRITES data_folder/main/commercial/questionable_status_{vintage_string}.Rds  (:262)
      WRITES data_folder/main/commercial/landings_cleaned_{vintage_string}.Rds     (:278)
3.  A02_make_daily_stats.R      → camsid_specific_cleaned_, daily_ma_, state_ma_,
                                   stockarea_ma_, gear_ma_  (:274, :322, :357, :390, :423)
4.  A03_make_dealer_stats.R     → dlrid_historical_stats_, dlrid_lag_stats_ (:87, :157)
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
      READS questionable_status_{vintage_string}.Rds (:97)
      WRITES data_folder/predictions/excluded_from_estimation_dataset_{...}.Rds (:117)

[RETIRED — 00_commercial_processing_wrapper.do:1 "this chain has been retired"]
    DO NOT RUN. Superseded by the R chain above. Listed for historical
    reference so the .dta files already on disk can be traced to a producer.
2'. A01_make_landings_cleaned.do  → $data_main\commercial\landings_cleaned_${vintage_string}.dta (:205)
3'. A02_make_daily_stats.do       → daily_ma_, state_ma_, stockarea_ma_, gear_ma_ (:219-282)
4'. A03_make_dealer_stats.do      → dlrid_historical_stats_, dlrid_lag_stats_ (:65, :109)
5'. A04_make_moving_average_prices.do → grand_moving_average_prices_ (:250)
    (No Stata B01/B02 equivalent ever existed — the ML data-prep stage is
     R-only, which is part of why this chain could not stand alone.)
```

### Stage 3 — Tilefish processing (parallel to Stage 2, independent)

```
[WRAPPER — 00_tilefish_processing_wrapper.R]
8.  A01_make_tilefish_landings_cleaned.R  (reads EXTERNAL DataPull)
      WRITES no_codes.Rds                                  (:134)
      WRITES questionable_tilefish_status_{vintage_string}.Rds (:264)
      WRITES tilefish_landings_cleaned_{vintage_string}.Rds    (:280)
9.  A02_make_daily_tilefish_stats.R → camsid_tilefish_specific_cleaned_,
      daily_tilefish_ma_, state_tilefish_ma_, gear_tilefish_ma_
      (:179, :227, :262, :294)
      NOTE: no stockarea_ equivalent — the commercial chain writes five files here,
      tilefish writes four.
10. A03_make_tilefish_dealer_stats.R → dlrid_tile_lag_stats_ (:80)
      NOTE: no dlrid_historical_ equivalent — commercial writes two, tilefish one.
11. A04_make_tilefish_moving_average_prices.R → tile_grand_moving_average_prices_ (:162)
12. B01_data_prep_tilefish_ml.R
      RE-DERIVES vintage_string from disk (:21-24); out_data_string <- Sys.Date() (:28)
      WRITES tilefish_{original_combined,unclassified,estimation}_dataset*
             (:343, :352, :361)  — .Rds only, no .dta twin
13. B02_handle_not_in_tilefish_estimation_dataset.R
      RE-DERIVES vintage_string (:24-27)
      WRITES data_folder/predictions/excluded_from_estimation_dataset_{...}.Rds (:76)
      NOTE: same output stem as the commercial B02 (:117). Both write into
      data_folder/predictions/ using the same prefix, distinguished only by
      whatever vintage each happens to resolve.
```

### Stage 4 — Random forest: tune → train → interpret

```
[WRAPPER — batch_RF_run.sh, steps at :19-31]
14. tune_randomforest_nocluster.R                    (:19-21)
      READS  BSB_estimation_dataset{max vintage on disk}.Rds (:130-133)
      SOURCES modeltype_patterns.R (:72), background_logger.R (:117, container only),
              BSB.Classification.Recipe.R (:258), BSB.Workflow.Setup.R (:261)
      WRITES results/ranger/{data_pattern}{tuning_vintage}.Rds
             results/ranger/{tuning_pattern}{tuning_vintage}.Rds
             results/ranger/{best_param_pattern}{tuning_vintage}.Rds
      NOTE: tuning_vintage <- as.character(Sys.Date()) (:136) — comment at :135
            says this is "purposely set as today"
15. train_randomforest_nocluster.R                   (:24-26)
      Consumes the tuning output; fit_model gate at :272 (default 1 = full re-fit)
16. variable_importance_randomforest_nocluster.R     (:29-31)
```

### Stage 5 — Random forest post-processing (same batch, continues from Stage 4)

```
[WRAPPER — batch_RF_run.sh]
17. weighted_calibration.R        (:36-38)  → log beside script
      WRITES results/ranger/validation_preds{finalfit_vintage}.dta  (:238)
             ← haven::write_dta. AN R → STATA HANDOFF.
      WRITES results/ranger/final/... calibration object (:586)
      WRITES results/ranger/aggregate_uncounted_calibrated_test_predictions_* (:832)
      WRITES results/ranger/aggregate_nocal_predictions_* (:939)
18. writing/figure1.R             (:42-44)  → log beside script
--  writing/figure2.R             (:47-49)  OFF — "requires windows, run by hand"
19. render writing/predictions_heatmap.Rmd          (:52)
20. render writing/tuning_diagnostics.Rmd           (:56)
21. render writing/out_of_sample_predictions.Rmd    (:59)
      ** THIS IS THE PRODUCER OF THE LAA INPUTS. **
      WRITES data_folder/predictions/out_of_sample_predictions_YRS_{modeltype}{finalfit_vintage}.Rds  (:360)
      WRITES results/ranger/out_of_sample_predictions_disaggregated_{modeltype}{finalfit_vintage}.Rds (:423)
      WRITES data_folder/predictions/ambitious_out_of_sample_predictions_YRS_{modeltype}{finalfit_vintage}.Rds  (:497)
      → Stage 7 (LAA/CAA/WHAM) must run AFTER this step. Verified dependency.
22. plot_ROC_curves.R             (:62-64)  → log beside script
--  render writing/Economic_informed_stock_assessments.Rmd  (:82) OFF, "not in pipeline"

[WRAPPER — batch_tile_RF_run.sh]
23. fit_tilefish_classification.R (:16-18)
    Depends on Stage 3 output (tilefish_estimation_dataset*.Rds, :130-133).
    ALSO READS three CSVs that nothing in this repo writes — hand-placed:
      data_folder/main/tilefish/tilefish_lengths2007.csv  (:993)
      data_folder/main/tilefish/tilefish_keyfile.csv      (:995)
      data_folder/main/tilefish/tilefish_lengths2015.csv  (:997)
    WRITES results/tilefish/{data split, tuning, fold metrics, final fit, calibration}
      (:211, :259, :263, :332, :521)
    WRITES data_folder/predictions/tilefish_out_of-sample_predictions_{vintage}.csv (:1364)
      ^ note the filename typo: "out_of-sample", not "out_of_sample".
    Unlike the BSB chain, this single script does tune + train + predict + plot
    (~1600 lines, ~20 ggsave calls to images/tilefish/exploratory/).
```

### Stage 6 — Stata analysis

```
[WRAPPER — 00_analysis_wrapper.do]
24. bsb_simple_hedonic.do
      READS  ${data_main}\commercial\BSB_original_combined_dataset${in_string}.dta (:14, :17)
             ← produced by R B01_data_prep_ml.R:507.  CROSS-LANGUAGE HANDOFF.
25. fmm_tries.do            ("I didn't really pursue this very much")
26. bsb_size_classifications.do
      WRITES $my_results/hedonic_table.md (:229) and 20+ sibling .md/.tex tables
             ← hedonic_table.md is consumed by writing/Appendix_Hedonic.Rmd:218
               (and :210 via knit_child).  CROSS-LANGUAGE HANDOFF.
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
(LAA_script.R:18-19)

29. LAA_script.R
      SOURCES get_intermediate_stockeff.R (:55), get_ages.R (:60),
              LAA_calculation_BSB.R (:61)  — in that order
      READS  out_of_sample_predictions_YRS_nocluster{vintage}.Rds
             ambitious_out_of_sample_predictions_YRS_nocluster{vintage}.Rds
             ← VERIFIED: written by writing/out_of_sample_predictions.Rmd:360, :497
               (Stage 5 step 21). Vintage resolved by list.files() + max() glob.
      READS  StockEff via Oracle (needs nefscdb_con from .Rprofile)
      WRITES header :12-13 says "Outputs: NONE." — but the sourced
             LAA_calculation_BSB.R writes 5 PDFs to results/ when plotson=TRUE
             (:202, :277, :345, :385, :426), and LAA_script.R itself writes
             results/{CAA,WAA}_comparison_{UNC_only,all}.pdf (:402, :450, :514, :563).
      Purpose: verification/decomposition, builds five parallel LAA series.

30. CAA_calculation.R    (function definition, CAA_calculation() at :39)
      READS data_folder/intermediate/Comm.discards.at.age.RDATA via load() (:49)
            ← nothing in this repo writes this file. EXTERNAL BOUNDARY.

31. fit_BSB_WHAM/fit_BSB_WHAM.R
      SOURCES every .R in R_code/LAA_calculation/ whose name lacks "script"
              (:37-40, list.files + grepl filter + lapply(source))
              ← this pulls in BOTH LAA_calculation.R and LAA_calculation_BSB.R,
                which define the same function name. See F-7.
      Opens its own Oracle connection interactively via
              rstudioapi::askForPassword() (:53-56)
      READS  data_folder/assessment/BSB_2025MT_Input.rds (:42)
             data_folder/predictions/out_of_sample_predictions_YRS_*.Rds (:59-61)
             data_folder/assessment/BSB_2025MT_Fit.rds (:122)
      CALLS  get_intermediate_stockeff() (:64), reallocate_market_categories() (:74),
             CAA_calculation() (:83)
      WRITES data_folder/assessment/BSB_Apportion_Fit.rds (:114)
      NOTE: uses bare relative paths, not here(). See F-10.

[UNCLEAR / STANDALONE — LAA cluster, relationship not resolved]
- LAA_calculation.R              (defines LAA_calculation() at :41; exercised by
                                  LAA_test_script.R:56)
- LAA_calculation_BSB.R          (defines LAA_calculation() at :46 — SAME NAME,
                                  different signature. Sourced by LAA_script.R:61)
- LAA_calculation_BSB_old.R      (defines LAA_calculation_old() at :55; superseded.
                                  No longer sourced by anything — see F-6)
- LAA_test_script.R              (test harness)
- LAA_investigation_script.R     (sources get_intermediate_stockeff.R:69,
                                  reallocate_market_categories.R:75, get_ages.R:76)
- test_refactor_script.R         (compares old vs new LAA implementations;
                                  currently sources ITSELF at :24 — see F-6)
- get_ages.R, get_intermediate_stockeff.R, reallocate_market_categories.R
                                 (function definitions, no side effects)
```

### Stage 8 — Manuscript assembly

```
[MANUAL — the render call is commented out at batch_RF_run.sh:82]
32. render writing/Economic_informed_stock_assessments.Rmd
      SOURCES modeltype_patterns.R (:145), predict_byhand.R (:146)
      Sets modeltype<-"nocluster" (:138), search_type<-"Advanced" (:141)
      Sets data_vintage_string<-"2026-05-28" (:134) — HARD-CODED, and inherited
        by the child documents. See F-9.
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
| `R_code/analysis/fit_random_forest/estimate_randomforest.R` | Uses `modeltype<-"standard"` / `search_type<-"Initial"` — the only script on the `"standard"` path. Not referenced by `batch_RF_run.sh`. The predecessor of the `tune`/`train` split. |
| `R_code/analysis/fit_random_forest/test_sampling.R` | A scratch/experiment file. No wrapper reference. |
| `writing/figure_extra.R` | No wrapper reference and no data dependency traced to the rest of the pipeline. Not called by `batch_RF_run.sh`, unlike `figure1.R` and `figure2.R`. |
| `writing/*.Rmd` (the reporting layer) | See the R Markdown inventory below. |
| `R_code/analysis/fit_BSB_WHAM/compare_png/compare_model_figs.Rmd` | Figure-comparison report; no wrapper reference. |
| `R_code/.../tilefish/TilefishProject.Rmd` | Duplicates the tilefish wrapper's setup block (`:33-39`) but as a notebook, and sources `gear_market_helpers.R` at `:44`. A parallel manual path to wrapper #2; its own comment at `:46` notes "final data prep, missing source". |

---

## Stata Global Macro Trace

Only globals used across more than one script are listed.

*(Task note: tracing Stata globals is no longer a required task for this document. The section is retained and kept current because the Stata analysis chain is still live.)*

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
Read by: A01_make_landings_cleaned.do (lines 23, 67, 176) — RETIRED chain only
Reassigned: NOT FOUND — appears stable
Note:    EXTERNAL BOUNDARY. Now read only by retired code. The live equivalent
         is the R object `my_datapull`, re-derived in each R wrapper at :25-26.
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
Read by: 00_commercial_processing_wrapper.do (4, 5, 7, 8) — RETIRED chain only,
         and those lines sit inside the file's /* ... */ comment block.
         No live consumer.
Reassigned: NOT FOUND — appears stable

Global: $analysis_code   Defined: folder_setup_globals.do:20
Read by: 00_analysis_wrapper.do (4, 7, 10, 13, 17)
Reassigned: NOT FOUND — appears stable

Global: $data_main       Defined: folder_setup_globals.do:32
Read by: all 5 analysis .do files; the retired A01-A04 .do files;
         vintage_lookup_and_reset.ado:8; folder_vintage_lookup_and_reset.ado:15
Reassigned: NOT FOUND — appears stable

Global: $data_external   Defined: folder_setup_globals.do:30
Read by: NOT FOUND — its only reader, extract_data_from_FRED.do, has been
         REMOVED from this repo. Now defined but never read.
Reassigned: NOT FOUND

Global: $my_results      Defined: folder_setup_globals.do:40
Read by: all 5 analysis .do files (log using / collect export)
Reassigned: NOT FOUND — appears stable

Global: $intermediate_results   Defined: folder_setup_globals.do:39
Read by: NOT FOUND — defined but never read in this repo

Global: $my_images / $exploratory / $my_tables / $my_adopath / $R_code /
        $extract_process / $extraction_code / $data_internal / $data_intermediate
Defined: folder_setup_globals.do:44, 45, 48, 22, 21, 17, 18, 29, 34
Read by: $exploratory ← bsb_size_classifications_V2.do
         $my_adopath  ← folder_setup_globals.do:51 (adopath +)
         Others: NOT FOUND read anywhere in this repo.
```

### Vintage globals — the two that actually drive filenames

```
Global: $vintage_string          ← the OUTPUT vintage
Defined: folder_setup_globals.do, line 57  →  $today_date_string  (i.e. today, YYYY_MM_DD)
Read by (LIVE):    bsb_size_classifications.do (709)
                   mlogit_prediction_summary.do (18)
                   vintage_lookup_and_reset.ado (39, 47, 50, 52)
                   folder_vintage_lookup_and_reset.ado (44, 52, 55, 57)
Read by (RETIRED): A01_make_landings_cleaned.do (205)
                   A02_make_daily_stats.do (24, 193, 219, 239, 260, 282)
                   A03_make_dealer_stats.do (65, 76, 109)
                   A04_make_moving_average_prices.do (21, 250)
REASSIGNED: vintage_lookup_and_reset.ado, line 51
            folder_vintage_lookup_and_reset.ado, line 56
            Both overwrite $vintage_string with interactive user input.
            The first of these fires from folder_setup_globals.do:59 during setup.
Note:    The live dependency that matters is bsb_size_classifications.do:709
         WRITING mlogit_estimation_dataset_${vintage_string}.dta and
         mlogit_prediction_summary.do:18 READING it back. Those two steps must
         run in the SAME session, or the vintage will not match.
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
                   (underscores; inside the file's comment block, so it does not
                   execute as the file currently stands)
Read by (LIVE):    bsb_simple_hedonic.do (1, 13, 14, 17)
                   bsb_size_classifications.do (2, 22, 27)
                   bsb_size_classifications_V2.do (1, 17, 22)
                   fmm_tries.do (1, 19, 20, 23)
                   mlogit_prediction_summary.do (1)
Read by (RETIRED): A01_make_landings_cleaned.do (23, 67, 176)
                   A03_make_dealer_stats.do (18)
REASSIGNED: Only one LIVE definition remains, so there is no live same-session
            clobbering. The risk returns only if the retired wrapper is
            un-commented and run, which would leave $in_string in the underscore
            format for the remainder of the session. See F-1.
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
└── tilefish/A01..A04, B01, B02                      :37, :38, :41, :44, :48, :51

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
├── helpers/background_logger.R                      :107   [container branch only]
└── (BSB.Classification.Recipe.R :201, BSB.Workflow.Setup.R :208  BOTH COMMENTED OUT)

weighted_calibration.R  →  modeltype_patterns.R :110, predict_byhand.R :111
plot_ROC_curves.R       →  modeltype_patterns.R :71,  predict_byhand.R :72
estimate_randomforest.R →  BSB.Classification.Recipe.R :238, BSB.Workflow.Setup.R :239

fit_tilefish_classification.R
├── helpers/background_logger.R                      :109   [container branch only]
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

LAA_test_script.R      →  LAA_calculation/LAA_calculation.R :56

test_refactor_script.R
├── LAA_calculation/test_refactor_script.R           :24   ** SOURCES ITSELF — see F-6 **
├── LAA_calculation/get_intermediate_stockeff.R      :35
└── LAA_calculation/LAA_calculation_BSB.R            :36

fit_BSB_WHAM.R
└── every .R in R_code/LAA_calculation/ whose filename lacks "script"  :37-40
    (list.files + grepl filter + lapply(source); resolves to CAA_calculation.R,
     LAA_calculation.R, LAA_calculation_BSB.R, LAA_calculation_BSB_old.R,
     get_ages.R, get_intermediate_stockeff.R, reallocate_market_categories.R)
    ** two of these define the same function name — see F-7 **

r_oracle_connection.R  →  project_logistics/R_paths_libraries.R :19

TilefishProject.Rmd    →  helpers/gear_market_helpers.R :44

writing/*.Rmd  →  modeltype_patterns.R + predict_byhand.R
                  (calibration_and_validation :128-129,
                   Economic_informed_stock_assessments :145-146,
                   out_of_sample_predictions :127-128,
                   predictions_heatmap :121-122,
                   tuning_diagnostics :130-131)
                  predictions_heatmap.Rmd also has BSB.Classification.Recipe.R (:212)
                  and BSB.Workflow.Setup.R (:214) COMMENTED OUT.
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
REASSIGNED by DISK SCAN. In total 23 files (16 .R, 7 .Rmd) resolve some vintage
            this way, all with the same idiom:
             list.files(<dir>, pattern=glob2rx("<stem>*Rds")) |> gsub |> max()
Sites that overwrite `vintage_string` specifically:
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
  writing/{estimate_multinomial:90, out_of_sample_predictions:172,
           predictions_heatmap:165, reading_ranger_results:189,
           tuning_diagnostics:174, calibration_and_validation:172}.Rmd
  writing/figure1.R:37-40                       (via a `dataset_name` variable)
Related scan variables using the same idiom: data_vintage_string,
  raw_oos_data_vintage_string, predictions_vintage (fit_BSB_WHAM.R:59-61),
  and the prediction-file globs in LAA_script.R, LAA_test_script.R,
  LAA_investigation_script.R.
HARD-CODED (does not scan):
  market_category_aggregations.R:36                   →  "2025-07-28"
  market_category_price_plots.R:36                    →  "2025-07-28"
  market_category_bau_allocation.R:33                 →  "2026-05-28"
  writing/Economic_informed_stock_assessments.Rmd:134 →  "2026-05-28"
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
Read by: :139-142 to name the data-split, tuning, best-param and final-fit files.
Effect:  Every tuning run creates a NEW dated artifact set rather than
         overwriting. Downstream scripts then pick these up by max() scan.
```

```
Object: data_vintage_string
Defined by DISK SCAN of results/ranger/ in six files:
         calibration_and_validation.Rmd:150-153
         out_of_sample_predictions.Rmd:150-153
         predictions_heatmap.Rmd:143-146
         reading_ranger_results.Rmd:172-175
         tuning_diagnostics.Rmd:153-156
         plot_ROC_curves.R:91
Defined by ASSIGNMENT elsewhere:
         Economic_informed_stock_assessments.Rmd:134  →  HARD-CODED "2026-05-28"
         summary_tables.Rmd:88                        →  <- finalfit_vintage
READ BUT NEVER DEFINED IN: writing/Appendix_Hedonic.Rmd:18
Mechanism: Appendix_Hedonic.Rmd is a CHILD document, pulled in by
         Economic_informed_stock_assessments.Rmd:718, so it inherits the parent's
         environment — specifically the parent's HARD-CODED :134 value, not a
         scanned one. Run standalone it fails with "object not found".
Assessment: This is the R analogue of Stata's cross-script global-scope leakage,
         and it carries the same risk: the child's behaviour depends on what the
         parent happened to set. Here the parent sets a pinned value. See F-9.
```

```
Objects: nefscdb_con, db1, connection, mkt.res
Defined: NOT IN THIS REPO
Read by: LAA_script.R (header :16 states nefscdb_con must exist via .Rprofile)
         LAA_investigation_script.R:121  (connection <- eval(nefscdb_con))
         test_refactor_script.R:19       (connection <- eval(nefscdb_con))
         compare_biostat_rf_output.R:4   (connection = db1)  and :16 (mkt.res)
Assessment: EXTERNAL BOUNDARY — session state supplied by the developer's
         .Rprofile. compare_biostat_rf_output.R additionally depends on `mkt.res`,
         which is a return value of get_intermediate_stockeff(); the script does
         not create it, so it only runs after something else has populated the
         session.
```

```
conflicted::conflicts_prefer() is set in both R wrappers (:15-20 in each) and
in several helpers and LAA scripts. These are session-wide and will affect any
script sourced afterwards.
```

### `writing/` R Markdown inventory (inputs only)

Catalogued but **not** placed in a relative order. `writing/` holds 16 `.Rmd` files, including the manuscript.

| Report | Primary inputs | Notes |
|---|---|---|
| `Economic_informed_stock_assessments.Rmd` | ranger results; 4 child docs | The manuscript. Render is commented out in `batch_RF_run.sh:82`. Pins `data_vintage_string` at `:134`. |
| `build_summary_tables.Rmd` | `data_split`, `oos_data` from parent env | **Child** of the manuscript (`:472`). No YAML — cannot run standalone. |
| `Appendix_Hedonic.Rmd` | `BSB_original_combined_dataset{data_vintage_string}.Rds`; `results/hedonic_table.md` | **Child** (`:718`). Consumes a **Stata-generated** table via `knit_child` at `:210` and `child=` at `:218`. |
| `Appendix_DataSummaries.Rmd` | tables from parent env | **Child** (`:721`). |
| `CRediT.Rmd` | none | **Child** (`:881`). Prose only. |
| `predictions_heatmap.Rmd` | `BSB_estimation_dataset*`, ranger results | Rendered by `batch_RF_run.sh:52`. |
| `tuning_diagnostics.Rmd` | ranger tuning results | Rendered by `batch_RF_run.sh:56`. Fold-level ROC. |
| `out_of_sample_predictions.Rmd` | `BSB_estimation_dataset*`, ranger results | Rendered by `batch_RF_run.sh:59`. Produces the prediction files LAA consumes. |
| `calibration_and_validation.Rmd` | `results/ranger/{data_pattern}*`, `BSB_unclassified_dataset*` | Not in any wrapper. |
| `reading_ranger_results.Rmd` | ranger data/tuning/final results | Driven by `knit_ranger_results_in_loop.R`. **Own inline dispatcher** — see F-3. |
| `estimate_multinomial.Rmd` | `BSB_estimation_dataset*` (`:90`) | Not in any wrapper. |
| `summary_tables.Rmd` | estimation dataset | Not in any wrapper. |
| `investigate_fit.Rmd` | narrative; `eval=FALSE` chunks | Lab notebook, not a data product. |
| `mnl_logit.Rmd` | narrative/math | Methods prose. |
| `strategic_interactions.Rmd` | — | Narrative. Its "Deep Background" section at `:170` now reads "see manuscript"; the former references to `BSB_history.Rmd` and `BSB_economic_background.Rmd` have been removed along with those files. |
| `HakeandTileExploratoryAnalysis.Rmd` | DataPull repo; `in_string <- "2026-06-09"` at `:301`, plus hard-coded `2026-06-08`/`2026-06-09` filenames at `:29-30`, `:350`, `:592-599` | Exploratory. Comments at `:616-617` reference helper functions "loaded from source()" but the file has **no `source()` call**, so those functions must already be in the session. |
| `R_code/.../TilefishProject.Rmd` | duplicates tilefish wrapper setup `:33-39` | Notebook mirror of wrapper #2. Outside `writing/`. |
| `fit_BSB_WHAM/compare_png/compare_model_figs.Rmd` | WHAM output PNGs | Figure comparison. Outside `writing/`. |

---

## Known Issues

### F-1: `$in_string` points each pipeline at a different vintage

| Where | Line | Value |
|---|---|---|
| `00_analysis_wrapper.do` | `:1` | `2026-03-16` |
| `00_commercial_processing_wrapper.R` | `:29` | `"2026-05-01"` |
| `00_tilefish_processing_wrapper.R` | `:31` | `"2026-06-09"` |

All three use the hyphenated `YYYY-MM-DD` form, so filenames are consistent. The values differ because each pipeline points at an independently-refreshed DataPull vintage. The practical consequence is that the Stata analysis chain reads a **March** combined dataset while the R commercial chain was built from a **May** pull.

The retired `00_commercial_processing_wrapper.do` would set `$in_string` at `:3` using an underscore form (`2026_05_01`). That line is inside the file's comment block, so it does not currently execute; un-commenting the chain would leave that value, and that format, in effect for the rest of the Stata session.

Needs review.

### F-2: R `vintage_string` is overwritten mid-wrapper

`00_commercial_processing_wrapper.R:30` sets `vintage_string <- Sys.Date()`. That value governs `A01`–`A04`. Then `B01_data_prep_ml.R:66-69` discards it and re-derives `vintage_string` by scanning `data_folder/main/commercial/` for `landings_cleaned_*.Rds` and taking `max()`.

In a same-day run these agree. They diverge if:

- `A01`–`A04` ran on a different day than `B01`;
- an older `landings_cleaned_*.Rds` sorts lexicographically higher than the new one;
- the folder contains files from an unrelated run.

`max()` on a character vector is a lexicographic comparison. It happens to be correct for `YYYY-MM-DD`, but it is not a date comparison, and on an empty vector it returns `-Inf` with a warning rather than failing loudly. The tilefish wrapper has the identical pattern at `B01_data_prep_tilefish_ml.R:21-24`.

### F-3: Duplicated and divergent `modeltype` dispatcher

`helpers/modeltype_patterns.R` handles three model types (`standard` `:9`, `nocluster` `:18`, `TESTnocluster` `:29`) and defines seven pattern variables each.

`writing/reading_ranger_results.Rmd:103` onward contains its own inline dispatcher that handles far more types (`fiveclass`, `noc5class`, `South_NOC`, `North_NOC`, `South_NOC_TEST`, `North_NOC_TEST`, `South_region_NOC`, and the `Tsubset` variants) but defines only three variables (`data_pattern`, `tuning_pattern`, `final_pattern`). The two are not kept in sync — a model type added to one will not exist in the other.

### F-4: `modeltype` options advertised but not implemented

The comment at `tune_randomforest_nocluster.R:67` reads:

```r
# OR "nocluster", or "fiveclass", or "noc5class" OR "standard"
```

`modeltype_patterns.R` implements neither `"fiveclass"` nor `"noc5class"` — setting either triggers `stop("Unknown modeltype")` at `:41`. `knit_ranger_results_in_loop.R:28` drives `modeltype = "nocluster_Tsubset"`, which the shared helper also does not implement; that works only because `reading_ranger_results.Rmd` uses its own dispatcher (F-3).

### F-5: Stata setup is interactive and will block a non-interactive run

`folder_setup_globals.do:59` calls `vintage_lookup_and_reset`. That program (`vintage_lookup_and_reset.ado:43`) issues a `_request(_vintage_string_bypass)` prompt and waits for input. Running `folder_setup_globals.do` in batch mode (`stata -b do ...`) will hang, or consume the next line of the file as the response.

Both `.ado` files behave this way. `folder_vintage_lookup_and_reset.ado` is a near-identical copy that scans subdirectories instead of files (prompt at `:48`, reassignment at `:56`), and is never called anywhere in this repo.


### F-7: Two different functions are both named `LAA_calculation`

| File | Line | Signature |
|---|---|---|
| `LAA_calculation.R` | `:41` | `LAA_calculation(species_itis, out_of_sample_predictions, fyr, lyr, connection)` |
| `LAA_calculation_BSB.R` | `:46` | `LAA_calculation(species_itis, out_of_sample_predictions, fyr, lyr, connection, sumflag, plotson, plotstub)` |

Both live in `R_code/LAA_calculation/`, and neither filename contains "script". `fit_BSB_WHAM.R:37-40` sources **every** `.R` in that directory whose name lacks "script":

```r
r_files <- list.files(path = "R_code/LAA_calculation/", pattern = "\\.[rR]$", full.names = TRUE)
r_files <- r_files[!grepl("script", r_files, ignore.case = TRUE)]
lapply(r_files, source)
```

So both definitions are evaluated, in `list.files()` order, and the later one silently masks the earlier. Whichever wins depends on the locale-dependent sort that `list.files()` returns — not on anything stated in the code.

The hand-run scripts avoid the ambiguity by sourcing one file explicitly (`LAA_script.R:61` takes `LAA_calculation_BSB.R`; `LAA_test_script.R:56` takes `LAA_calculation.R`), so this only bites through `fit_BSB_WHAM.R`. Directly related to the open question of which LAA implementation is canonical.

Flagging only; not resolving.

### F-9: Hard-coded personal paths and pinned vintages

Paths that will not resolve for another developer:

| Location | Path | Kind |
|---|---|---|
| `compare_biostat_rf_output.R:31` | `C:/Users/emily.liljestrand/Downloads/compare_BIOSTAT_RF.csv` | write target |
| `fit_BSB_WHAM.R:26, :32` | `C:/Users/emily.liljestrand/AppData/Local/R/win-library/...` (for `wham`) | library path |

Separately, several scripts pin a vintage as a literal rather than deriving it:

| Script | Line | Pinned vintage |
|---|---|---|
| `market_category_aggregations.R` | `:36` | `"2025-07-28"` |
| `market_category_price_plots.R` | `:36` | `"2025-07-28"` |
| `market_category_bau_allocation.R` | `:33` | `"2026-05-28"` |
| `writing/Economic_informed_stock_assessments.Rmd` | `:134` | `"2026-05-28"` |
| `compare_biostat_rf_output.R` | `:15` | `...2026-03-16.RDS` |
| `test_refactor_script.R` | `:13` | `...2026-06-15.rds` |
| `HakeandTileExploratoryAnalysis.Rmd` | `:29-30` | `2026-06-08`, `2026-06-09` |

These will silently read stale data, or fail, once those files age out. The manuscript's `:134` pin is the widest-reaching of them: because `Appendix_Hedonic.Rmd` is a child document, it inherits that pinned `data_vintage_string` rather than scanning for the current one.

### F-10: `fit_BSB_WHAM.R` clears session
`rm(list=ls())` at `:29` additionally clears the session, so anything a developer had set up by hand beforehand is discarded.

---

## Flags for Further

1. **Vintage skew (F-1).** Whether the Stata analysis chain should be reading a March dataset while the R commercial chain was built from a May pull. Noted as "fine" but intended to be moved to the May data pull with tables rebuilt.
2. **`estimate_randomforest.R` and `test_sampling.R`.** These predate the tune/train split and are believed retired.
3. **The `LAA_calculation/` cluster (F-6, F-7).** Which of `LAA_calculation.R`, `LAA_calculation_BSB.R`, and `LAA_calculation_BSB_old.R` is canonical. Still in development. The name collision in F-7 and the dead `_old` file in F-6 both hang on this decision.
4. **`writing/figure_extra.R`.** No wrapper reference and no traced data dependency. believed retired
5. **`runClass` has no fallback.** `'Local'` is tested for but never assigned, so a platform that is neither Linux nor Windows errors on an undefined object rather than falling back. Would only surface at runtime.
