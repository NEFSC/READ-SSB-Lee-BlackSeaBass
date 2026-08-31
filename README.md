# Black Sea Bass — Economic-Informed Stock Assessments

Code for *"Economic-informed stock assessments."*

Because the size of an individual fish determines the price of fish, we can invert that relationship to fill in gaps when we do not sample the lengths of those fish. There are five prevailing BSB market categories: Jumbo, Large, Medium, Small, and Unclassified. From 2020 to 2023, 5–10% of commercial landings were in the "Unclassified" market category, but no fish in that category were measured. We train a Random Forest on transactions data and use the fitted model to predict the market category of Unclassified landings. Those predictions are then pushed downstream into landings-at-age / catch-at-age reapportionment and, ultimately, into a WHAM stock assessment fit.

The repository also contains a **parallel tilefish pipeline** built on the same machinery, and the manuscript source in `writing/`.

[`DATAFLOW_BSB.md`](DATAFLOW_BSB.md) is the execution-order and data-flow reference: every wrapper, every toggle, the Stata global-macro trace, the R sourcing graph, and eight catalogued issues. This README is an orientation and quick start.

---

## Repository layout

```
READ-SSB-Lee-BlackSeaBass/
├── R_code/
│   ├── analysis/
│   │   ├── fit_random_forest/          # BSB classifier: tune → train → VI → calibrate
│   │   ├── fit_tilefish_random_forest/ # tilefish classifier (one big script)
│   │   ├── fit_BSB_WHAM/               # WHAM assessment fit
│   │   └── helpers/                    # shared: modeltype_patterns, predict_byhand, …
│   ├── LAA_calculation/                # landings-at-age / catch-at-age reapportionment
│   ├── data_extraction_processing/
│   │   ├── extraction/                 # Oracle / FRED pulls
│   │   └── processing/{commercial,tilefish}/   # A01–A04, B01–B02 + wrappers
│   └── project_logistics/              # R_paths_libraries.R
├── stata_code/
│   ├── analysis/                       # hedonic + multinomial logit models — LIVE
│   ├── data_extraction_processing/
│   │   ├── extraction/                 # EMPTY — FRED extraction moved to the DataPull repo
│   │   └── processing/
│   │       └── commercial/             # RETIRED — superseded by the R chain
│   ├── project_logistics/              # folder_setup_globals.do  ← start here in Stata
│   └── ado/                            # vintage_lookup_and_reset, folder_… variant
├── data_folder/
│   ├── raw/  external/  internal/  intermediate/
│   ├── main/                           # commercial outputs; main/tilefish/ for tilefish
│   ├── predictions/                    # out-of-sample prediction files
│   └── assessment/                     # WHAM inputs/fits
├── writing/                            # 16 .Rmd (manuscript + reports) + figure scripts
├── results/                            # Stata tables (.md/.tex), ranger/ model artifacts
├── images/                             # background/, descriptive/, exploratory/
├── tables/  documentation/             # documentation/project_logistics.md
└── DATAFLOW_BSB.md  README.md  License.txt
```

### The multi-repo assumption

This repo does **not** stand alone. `READ-SSB-Lee-BSB-DataPull` is a **hard dependency**: `A01_make_landings_cleaned.R` reads its raw landings, gear, and deflator files from there. Both R wrappers locate it as a **sibling directory**:

```r
# 00_commercial_processing_wrapper.R:25-26
my_datapull <- dirname(here())
my_datapull <- file.path(my_datapull, "READ-SSB-Lee-BSB-DataPull")
```

Nothing validates that the sibling exists. Keep the repos side by side:

```
BSB_mega_folder/
├── READ-SSB-Lee-BSB-DataPull/   # data pull, explore, background — upstream
├── READ-SSB-Lee-BlackSeaBass/   # this repo
└── PortChoice/                  # separate project, not referenced by this code
```

On the Stata side the equivalent is `$my_datapull`, built in `folder_setup_globals.do:13` from `$my_megadir`, which is in turn built from `${mynetwork}` — a global that must already exist in your `profile.do`. Note that `$my_datapull` is now read only by the retired Stata chain; the live path is the R one above.

---

## Prerequisites

**R** — the pipeline uses `here()` for in-repo paths, so it resolves from the repo root via the `.git` marker. There is no `.Rproj` in the repository.

Packages actually loaded across the codebase:

```
here tidyverse dplyr tidyr ggplot2 lubridate glue slider conflicted forcats magrittr
tidymodels hardhat probably discrim bonsai ranger nnet partykit vip butcher betacal
haven foreign readr janitor skimr scales viridis pals ggrepel kableExtra knitr
rmarkdown htmltools htmlwidgets plotly captioner pander tinytex future
DBI ROracle dbplyr survey srvyr fredr sf mapview comlandr
```

Two are not plain CRAN installs:

- **`wham`** is pinned to a specific commit and loaded from a hard-coded library path — `fit_BSB_WHAM.R:26,32` reference `timjmiller/wham@e7bd16e` (v2.1.0.9005) under a personal `AppData` path. **You will need to change that `lib.loc` to your own.**
- **`comlandr`** and **`betacal`** are likewise not on the default CRAN path for all users.

**Stata** — `folder_setup_globals.do:3` declares `version 15.1`, but `bsb_size_classifications.do` and `bsb_size_classifications_V2.do` use `collect`, which requires **Stata 17+**. Treat 17 as the floor for the analysis chain.

**Oracle client**, for `ROracle` against StockEff.

**Operating system.** Windows or Linux — the random-forest scripts branch on `Sys.info()['sysname']` and set thread counts per platform. There is no fallback branch: a platform that is neither errors on an undefined `runClass`.

- The two `.sh` wrappers need bash.
- `helpers/background_logger.R` shells out to `top` and `ps`, so it is Linux-only. It is guarded behind the container branch.
- `writing/figure2.R` is annotated "requires windows" and sits outside the batch script.

`folder_setup_globals.do` uses forward slashes throughout. The *consuming* Stata scripts still build paths with backslashes (e.g. `use "${data_main}\commercial\..."` in the analysis chain), so the tree is not fully portable — Windows tolerates the mix, Unix will not.

The developers mostly run the code on a container at NEFSC. You might be able to run on windows on a laptop, however the RF model takes a long time to run.

---

## Credentials

Nothing secret should land in the repo.

**Stata** — see [`documentation/project_logistics.md`](documentation/project_logistics.md).

**R** — set values in a keyring (`keyring::key_set()` / `keyring::key_get()`) or in an encrypted `.Rprofile` / `.Renviron`.

What the code actually expects to already exist in your session:

| Name | Needed by | Source |
|---|---|---|
| `nefscdb_con` | `LAA_script.R`, `LAA_investigation_script.R`, `test_refactor_script.R` | your `.Rprofile` (stated in `LAA_script.R:16`) |
| `FRED_API_KEY` | `FRED_extraction.R:8` | `.Renviron` / `.Rprofile` |
| Oracle id / password | `r_oracle_connection.R`, `dbi_extraction.R` | your own setup |
| Oracle password (prompt) | `fit_BSB_WHAM.R:53-56` | `rstudioapi::askForPassword()`, interactive |

`compare_biostat_rf_output.R` additionally assumes a connection object `db1` and a data frame `mkt.res` already exist in the session; it creates neither.

---

## Running the pipeline

Full sequence, with every dependency and toggle, is in **[`DATAFLOW_BSB.md` → Master Execution Sequence](DATAFLOW_BSB.md#master-execution-sequence)**. The short version:

### 0. Session setup

**Stata** — your `profile.do` must define `${mynetwork}`; everything else derives from it.

```stata
/* Sets ~20 path globals, adds stata_code/ado to the adopath,
   sets $vintage_string to today, then calls vintage_lookup_and_reset. */
do "path/to/stata_code/project_logistics/folder_setup_globals.do";
```

Heads-up: that last step is **interactive**. `vintage_lookup_and_reset` (`ado/vintage_lookup_and_reset.ado:43`) issues a `_request()` prompt asking whether to override `$vintage_string`. Press Enter to keep today's value. **This will hang a `stata -b` batch run.**

**R** — no setup file is required; the wrappers set their own variables. `R_code/project_logistics/R_paths_libraries.R` exists and defines path objects (and locates a Stata executable), but neither wrapper sources it.

### 1. Data Processing

Commercial processing is **R-only**. The Stata `A01`–`A04` chain under `stata_code/.../processing/commercial/` is **retired** (`00_commercial_processing_wrapper.do:1`, with the whole body inside a comment block); do not run it. It remains in the tree as the reference implementation the R port was made from.

```r
# Set in_string (input vintage from the DataPull repo) at the top of the wrapper first.
source(here("R_code", "data_extraction_processing", "processing",
            "commercial", "00_commercial_processing_wrapper.R"))
```

Runs `A01 → A02 → A03 → A04 → B01 → B02` unconditionally. Produces `landings_cleaned_*`, the daily/dealer/moving-average stats, and finally `BSB_{original_combined,unclassified,estimation}_dataset*.Rds`.

The wrapper creates `data_folder/main/commercial/` itself (`:28-29`) before sourcing anything. That directory is absent on a fresh checkout, so run the wrapper rather than the `A0*` scripts individually the first time. The tilefish wrapper does the same for `data_folder/main/tilefish/` (`:28-29`).

The `A0*` stages write **`.Rds` only**. The sole `.dta` outputs are the three `BSB_*_dataset` files from `B01_data_prep_ml.R:507,517,527`, written for the Stata analysis chain in step 4.

Tilefish is the same shape:

```r
source(here("R_code", "data_extraction_processing", "processing",
            "tilefish", "00_tilefish_processing_wrapper.R"))
```

### 2. Fit the Random Forest

```bash
# from the project root
./R_code/analysis/fit_random_forest/batch_RF_run.sh
```

This runs the **full chain**, nine steps: tune → train → variable importance → weighted calibration → `figure1.R` → three report renders (`predictions_heatmap`, `tuning_diagnostics`, `out_of_sample_predictions`) → ROC curves. Expect it to be very long-running; the tuning and training steps are the expensive ones. The VIP part is essentially another training fit. It's an "overnight job" on the NEFSC container with expanded threads and RAM (24 and 160GB).

The script's toggles are comment/uncomment, not variables. Two of the eleven steps are deliberately off: `writing/figure2.R` (`:47-49`, "requires windows — run by hand") and the manuscript render (`:82`, under "Next steps (deliberately not in pipeline)").

Model configuration (`modeltype`, `search_type`, `testing_fraction`, `bayes_tune`) is set **per script**, not passed in by the batch file — so changing model type means editing several files. See the [Toggle Catalog](DATAFLOW_BSB.md#toggle-catalog).

One toggle worth knowing before you re-run anything: `train_randomforest_nocluster.R:272` sets `fit_model = 1`, which fits the final model from scratch. Setting it to `0` short-cuts the expensive fit by reading the previous `final_ranger_fit` and prepped recipe back off disk, so you can iterate on the augment and calibration code below it.

**Failure behaviour:** both `.sh` files set `set -e` and `set -o pipefail`, and the nine steps are `&&`-chained. A failed step halts the batch immediately, skips everything downstream, prints no success message, and exits non-zero. The script creates `results/ranger/` itself (`mkdir -p`), since `tee` cannot and the directory is absent on a fresh checkout.

Note that the other log destinations are *not* auto-created — if you run the script from anywhere other than the project root, it will fail fast rather than scatter directories.

Tilefish: `./R_code/analysis/fit_tilefish_random_forest/batch_tile_RF_run.sh`. Tilefish is much faster because we are not expanding the observations to pounds and there are only 40,000 observations. It's under 1 hour to run. Its data-prep step is commented out at `:11-13`; uncomment it to chain the tilefish processing wrapper onto the fit.

### 3. Downstream — LAA / CAA / WHAM

`writing/out_of_sample_predictions.Rmd` (rendered as step 21 of the batch) is what **writes** `data_folder/predictions/out_of_sample_predictions_YRS_*.Rds` and its `ambitious_*` twin. Everything in `R_code/LAA_calculation/` consumes those, so it must run afterwards.

The LAA calculation scripts are hand-run — no wrapper calls them, and they say so in their own headers. `LAA_script.R` is the main driver; `fit_BSB_WHAM.R` fits the assessment. These were the last files to be developed and when we are satisfied they will also be added to `batch_RF_run.sh`.

Two things to know before running this stage:

- `fit_BSB_WHAM.R` sources *every* `.R` in `R_code/LAA_calculation/` whose filename lacks "script" (`:41-44`). That is also how the tidyverse reaches the script — it loads only `wham`, `ROracle`, `DBI`, `here` and `glue` itself. Two of the sourced files define a function called `LAA_calculation`, so one silently masks the other; nothing in the script calls it, so the collision is latent rather than live ([F-6](DATAFLOW_BSB.md#f-6-two-different-functions-are-both-named-laa_calculation)).
- `test_refactor_script.R` exists to diff the old and new LAA implementations against each other (`identical()` at `:59`). It **pins** its prediction input at `:13`, so it will not pick up a newer run ([F-7](DATAFLOW_BSB.md#f-7-hard-coded-personal-paths-and-pinned-vintages)).

### 4. Stata analysis (independent of steps 2–3) — still live

The commercial *processing* chain is retired; the Stata **analysis** chain is not.

```stata
* Sets $in_string, then runs five analysis do-files in order.
do "$analysis_code/00_analysis_wrapper.do";
```

This chain reads the `.dta` files that R's `B01_data_prep_ml.R` wrote, and `bsb_size_classifications.do` exports `results/hedonic_table*.md`, which `writing/Appendix_Hedonic.Rmd` pulls back in as a child document. The handoffs run in both directions — R is upstream of Stata for the data, Stata is upstream of R for the hedonic tables.

Run the five do-files in one session. `bsb_size_classifications.do:709` writes `mlogit_estimation_dataset_${vintage_string}.dta` and `mlogit_prediction_summary.do:18` reads it back by the same global; split them across sessions and the vintage will not match.

### How vintages are passed — and why R and Stata differ

This is the single most important thing to internalise before editing anything.

- **Stata** passes vintages explicitly by global macro: `$in_string` (input) and `$vintage_string` (output). They persist across `do` calls for the life of the session.
- **R** passes them by **scanning the disk**. Twenty-three files (17 `.R`, 6 `.Rmd`) re-derive a vintage with the same idiom:

  ```r
  vintage_string <- list.files(here("data_folder", "main", "commercial"),
                               pattern = glob2rx("BSB_estimation_dataset*Rds"))
  vintage_string <- gsub("BSB_estimation_dataset", "", vintage_string)
  vintage_string <- gsub(".Rds", "", vintage_string)
  vintage_string <- max(vintage_string)
  ```

  Consequence: the `vintage_string <- Sys.Date()` set in the wrapper governs only `A01`–`A04`. `B01_data_prep_ml.R:66-69` discards it and picks whatever sorts highest on disk. `max()` here is a lexicographic string comparison, not a date comparison, and returns `-Inf` with a warning on an empty folder rather than failing loudly.

  A handful of scripts opt out of the scan entirely and pin a vintage as a literal — including the manuscript itself (`Economic_informed_stock_assessments.Rmd:134`), whose pinned value is inherited by its child documents.

---

## Known issues and open questions

Full list with citations: **[`DATAFLOW_BSB.md` → Known Issues](DATAFLOW_BSB.md#known-issues)**. The ones most likely to bite a new developer:

| | Issue |
|---|---|
| **F-1** | The three `in_string` values share a format but point at different DataPull vintages: the Stata analysis chain reads a **March** dataset (`00_analysis_wrapper.do:1`) while the R commercial chain was built from a **May** pull. |
| **F-2** | R's disk-scan vintage resolution (above) silently decouples downstream scripts from the wrapper. |
| **F-5** | Stata setup is interactive and will hang a batch run. |
| **F-6** | `LAA_calculation.R` and `LAA_calculation_BSB.R` both define `LAA_calculation()`. `fit_BSB_WHAM.R` sources both, so one masks the other in locale-dependent `list.files()` order. |
| **F-7** | Hard-coded personal paths (`C:/Users/emily.liljestrand/...`) and seven scripts with pinned vintage strings that will silently go stale. |
| **F-8** | `fit_BSB_WHAM.R` opens with `rm(list=ls())`, discarding anything you had set up by hand. |

**Open questions** — the full list is at the end of `DATAFLOW_BSB.md`:

- Which of `LAA_calculation.R`, `LAA_calculation_BSB.R`, and `LAA_calculation_BSB_old.R` is canonical (F-6 depends on this; `LAA_calculation_BSB_old.R` survives only because `test_refactor_script.R` diffs the two implementations).
- Whether `estimate_randomforest.R` and `test_sampling.R` are retired (`out_of_sample_predictions_StockAssess.Rmd` already has been, and was deleted).
- Whether `writing/figure_extra.R` is live — it has no wrapper reference and no traced dependency.
- Whether `00_analysis_wrapper.do` should be moved onto the May data pull and its tables rebuilt.

---

## Where to go for more detail

| Document | Contents |
|---|---|
| **[`DATAFLOW_BSB.md`](DATAFLOW_BSB.md)** | Wrapper inventory, full toggle catalog, master execution sequence, Stata global-macro trace, R sourcing graph, `writing/` Rmd inventory, eight known issues and five review flags. Standalone — assumes no context. |
| [`documentation/project_logistics.md`](documentation/project_logistics.md) | Stata-side credential handling. |
| [`License.txt`](License.txt) | License. |
| `writing/investigate_fit.Rmd` | Narrative lab notebook on model-fit decisions — why the pooled model was kept and the North/South split abandoned. Useful modelling context. |

---

## NOAA Requirements

This repository is a scientific product and is not official communication of the National Oceanic and Atmospheric Administration, or the United States Department of Commerce. All NOAA GitHub project code is provided on an 'as is' basis and the user assumes responsibility for its use. Any claims against the Department of Commerce or Department of Commerce bureaus stemming from the use of this GitHub project will be governed by all applicable Federal law. Any reference to specific commercial products, processes, or services by service mark, trademark, manufacturer, or otherwise, does not constitute or imply their endorsement, recommendation or favoring by the Department of Commerce. The Department of Commerce seal and logo, or the seal and logo of a DOC bureau, shall not be used in any manner to imply endorsement of any commercial product or activity by DOC or the United States Government."

---

## Project metadata

1. **Who worked on this project:** Min-Yang Lee and Emily Liljestrand. `writing/CRediT.Rmd` credits a second author (EL), and parts of the WHAM and BIOSTAT-comparison code carry Emily Liljestrand's paths.
1. **When this project was created:** Summer 2024
1. **What the project does:** Black Sea Bass related projects
1. **Why the project is useful:** Black Sea Bass is awesome
1. **How users can get started:** Read the Prerequisites and "Running the pipeline" sections above, then [`DATAFLOW_BSB.md`](DATAFLOW_BSB.md)
1. **Where users can get help:** email me or open an issue
1. **Who maintains and contributes:** Min-Yang

## License

See the [license file](License.txt).
