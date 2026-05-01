# =============================================================================
# Script:  gear_market_helpers.R
# Purpose: Shared helper functions used across multiple BSB analysis scripts:
#          (1) apply_gear_categories()       — maps negear codes to 5 gear groups
#          (2) apply_market_rebinning()       — standard market category rebinning
#          (3) apply_market_rebinning_dealers() — dealers-analysis variant
#          (4) apply_grade_cleaning()          — standardizes grade_desc values
# Notes:   IMPORTANT -- this rebinning makes sense for black sea bass, but may not 
#          be optimal for another fishery. Use with care
#          Gear mapping and market rebinning logic appears in multiple Stata
#          scripts (bsb_exploratory.do, bsb_exploratory_dealers.do,
#          prices_by_category.do).  Extracted here to avoid triplication.
#          If gear or market rules change, update this file only.
#
#          GEAR CATEGORY MAPPING
#          Maps NEFSC negear codes into 5 final categories:
#          LineHand, Trawl, Gillnet, PotTrap, Misc (Dredge + Seine + Unknown).
#          NOTE: negear 71 (otter trawl) and 160 (mid-water pair trawl) are
#          listed under Trawl in the Stata code but later overridden by Seine;
#          they end up as Misc.  case_when order preserves that final state.
#
#          MARKET CATEGORY REBINNING
#          Standard: MX→UN, PW+ES→SQ (Small), XG→JB (Jumbo)
#          Dealers:  MX→UN, PW→ES (Pee Wee kept as Extra Small, not merged)
#          See README for full code table.  Update all three calling scripts
#          (bsb_exploratory.R, bsb_exploratory_dealers.R, prices_by_category.R)
#          if rebinning rules change.
# =============================================================================


# -----------------------------------------------------------------------------
# apply_gear_categories()
# Adds column `mygear` to df based on `negear`.
# Final categories: LineHand, Trawl, Gillnet, PotTrap, Misc.
# Rows with unrecognized negear codes get NA.
# -----------------------------------------------------------------------------
apply_gear_categories <- function(df) {
  df %>%
    mutate(
      mygear = case_when(
        # LineHand (hooks, lines, rods, cast nets, weirs, handlines)
        negear %in% c(10, 20, 21, 22, 30, 34, 40, 60, 62, 65, 66,
                      90, 250, 251, 330, 340, 380, 410, 414, 420) ~ "LineHand",
        negear >= 220 & negear <= 230                              ~ "LineHand",

        # Seine → Misc (placed before Trawl range: negear 71 and 160 are listed
        # under Trawl in Stata but overridden by Seine; Stata's last-replace-wins
        # means they end up Seine → Misc.  Listing here first achieves same result.)
        negear %in% c(70, 71, 160, 360)   ~ "Misc",   # Seine → Misc
        negear >= 120 & negear <= 124      ~ "Misc",   # Seine → Misc

        # Trawl (otter, beam, pair, mid-water — excludes 71 & 160 handled above)
        negear >= 50  & negear <= 59  ~ "Trawl",
        negear %in% c(150, 170, 350, 351, 353, 370, 450) ~ "Trawl",

        # Gillnet
        negear >= 100 & negear <= 117 ~ "Gillnet",
        negear %in% c(500, 520)       ~ "Gillnet",

        # PotTrap (pots, traps, weirs, pounds)
        negear >= 180 & negear <= 217 ~ "PotTrap",
        negear >= 300 & negear <= 301 ~ "PotTrap",
        negear %in% c(80, 140, 141, 142, 143, 240, 260, 270, 320, 321, 322, 323) ~ "PotTrap",

        # Dredge + Unknown → Misc
        negear >= 381 & negear <= 383 ~ "Misc",
        negear %in% c(132, 400)       ~ "Misc",
        negear == 999                 ~ "Misc",

        TRUE ~ NA_character_
      )
    )
}


# -----------------------------------------------------------------------------
# apply_market_rebinning()
# Standard rebinning for bsb_exploratory and prices_by_category.
# Returns df with cleaned market_code and market_desc (ordered factor).
# Rules: MX→UN, PW+ES→SQ (Small), XG→JB (Jumbo), proper-case titles.
# -----------------------------------------------------------------------------
apply_market_rebinning <- function(df) {
  market_levels <- c("Jumbo", "Large", "Medium", "Small", "Extra Small", "Unclassified")

  df %>%
    mutate(
      # MX (Mixed/Unsized) → UN (Unclassified)
      market_desc = if_else(market_desc == "MIXED OR UNSIZED", "UNCLASSIFIED", market_desc),
      market_code = if_else(market_code == "MX",              "UN",           market_code),

      # PW (Pee Wee) + ES (Extra Small) → SQ (Small)
      market_code = if_else(market_code %in% c("PW", "ES"), "SQ", market_code),
      market_desc = if_else(market_desc %in% c("PEE WEE (RATS)", "EXTRA SMALL"), "SMALL", market_desc),

      # XG (Extra Large) → JB (Jumbo)
      market_desc = if_else(market_desc == "EXTRA LARGE", "JUMBO", market_desc),
      market_code = if_else(market_code == "XG",          "JB",    market_code),

      # Title-case and fix "Medium Or Select"
      market_desc = str_to_title(market_desc),
      market_desc = if_else(market_desc == "Medium Or Select", "Medium", market_desc),

      market_desc = factor(market_desc, levels = market_levels)
    )
}


# -----------------------------------------------------------------------------
# apply_market_rebinning_dealers()
# Dealers-analysis variant: PW stays as ES (Extra Small), not merged into Small.
# NOTE: intentionally differs from apply_market_rebinning() — Pee Wee is kept
# as a separate Extra Small record to preserve finer size detail for
# dealer-pattern analysis.  No XG→JB rule here.
# -----------------------------------------------------------------------------
apply_market_rebinning_dealers <- function(df) {
  df %>%
    mutate(
      # MX (Mixed/Unsized) → UN (Unclassified)
      market_desc = if_else(market_desc == "MIXED OR UNSIZED",  "UNCLASSIFIED", market_desc),
      market_code = if_else(market_code == "MX",                "UN",           market_code),

      # MEDIUM OR SELECT → MEDIUM
      market_desc = if_else(market_desc == "MEDIUM OR SELECT", "MEDIUM", market_desc),

      # PEE WEE (RATS) → EXTRA SMALL (code PW → ES; stays in Extra Small, not merged to Small)
      market_desc = if_else(market_desc == "PEE WEE (RATS)", "EXTRA SMALL", market_desc),
      market_code = if_else(market_code == "PW",             "ES",          market_code)
    )
}


# -----------------------------------------------------------------------------
# apply_grade_cleaning()
# Standardizes grade_desc values and returns an ordered factor.
# NOTE: Stata maps UNGRADED → "Round" (not "Ungraded"). Faithfully reproduced.
# -----------------------------------------------------------------------------
apply_grade_cleaning <- function(df) {
  df %>%
    mutate(
      grade_desc = case_when(
        grade_desc == "LIVE (MOLLUSCS SHELL ON)" ~ "Live",
        grade_desc == "UNGRADED"                 ~ "Round",  # NOTE: Stata maps UNGRADED → Round
        TRUE ~ str_to_title(grade_desc)
      ),
      grade_desc = factor(grade_desc, levels = c("Round", "Live", "Ungraded"))
    )
}
