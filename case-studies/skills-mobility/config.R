# config.R -- shared paths, constants, and the cross-cycle PIAAC variable map.
# Sourced by every script in R/. No analysis logic here.

suppressWarnings(suppressMessages({
  library(dplyr); library(tidyr); library(readr); library(stringr); library(purrr)
}))

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---- paths -------------------------------------------------------------------
# Project root: env var override, else the working directory (scripts are run
# from the project root, e.g. `Rscript R/03_analyse.R`).
PROJ <- Sys.getenv("PIAAC_PROJ", unset = getwd())
if (!dir.exists(file.path(PROJ, "R")) && dir.exists("R")) PROJ <- getwd()
RAW_DIR   <- file.path(PROJ, "data", "raw")
DERIV_DIR <- file.path(PROJ, "data", "derived")
OUT_FIG   <- file.path(PROJ, "outputs", "figures")
OUT_TAB   <- file.path(PROJ, "outputs", "tables")
ONTO_DIR  <- file.path(PROJ, "ontology")
for (d in c(RAW_DIR, DERIV_DIR, OUT_FIG, OUT_TAB, ONTO_DIR)) dir.create(d, showWarnings = FALSE, recursive = TRUE)

# ---- data sources (open, no restricted licence) ------------------------------
# OECD PIAAC public-use files, served from the OECD web file store (open
# directory, not behind the Cloudflare-gated www.oecd.org CDN).
PIAAC_BASE <- "https://webfs.oecd.org/piaac"
SOURCES <- tibble::tribble(
  ~cycle, ~year, ~url,                                                          ~file,         ~delim,
  "CY1",  2012L, paste0(PIAAC_BASE, "/cy1-puf-data/CSV/prggbrp1.csv"),          "prggbrp1.csv", ",",
  "CY2",  2023L, paste0(PIAAC_BASE, "/cy2-puf-data/CSV/prggbrp2.csv"),          "prggbrp2.csv", ";"
)
# SPSS files (carry embedded value labels; used once to source the ontology
# value-label definitions, not by the analysis pipeline). Served zipped.
SOURCES_SAV <- tibble::tribble(
  ~cycle, ~url,                                                          ~file,
  "CY1",  paste0(PIAAC_BASE, "/cy1-puf-data/SPSS/prggbrp1_sav.zip"),     "prggbrp1_sav.zip",
  "CY2",  paste0(PIAAC_BASE, "/cy2-puf-data/SPSS/PRGGBRP2_sav.zip"),     "PRGGBRP2_sav.zip"
)

# ---- replicate-weight design (PIAAC) -----------------------------------------
# PIAAC point estimates use the final sample weight SPFWT0; sampling variance
# uses the 80 jackknife replicate weights SPFWT1..SPFWT80 with the OECD formula
#   Var = sum_{r=1}^{80} (theta_r - theta_0)^2   (no Fay factor).
# Proficiency uses the 10 plausible values, combined by Rubin's rules.
W_FINAL  <- "SPFWT0"
W_REP    <- sprintf("SPFWT%d", 1:80)
N_REP    <- 80L
PV_NUM   <- sprintf("PVNUM%d", 1:10)   # numeracy plausible values
PV_LIT   <- sprintf("PVLIT%d", 1:10)   # literacy plausible values

# ---- cross-cycle variable map ------------------------------------------------
# Each analysis concept -> the source column in each cycle. Verified by direct
# inspection of the two CSV headers (CY1 1328 cols comma-delimited; CY2 2483
# cols semicolon-delimited). "_TC1" suffixes in CY2 are the OECD's own
# trend-coded-to-Cycle-1 derivations, so they are the comparable versions.
VARMAP <- tibble::tribble(
  ~concept,            ~cy1,            ~cy2,             ~note,
  "parental_edu",      "PARED",         "PAREDC2",        "highest ISCED of either parent, 3 bands (1 low,2 med,3 high); D/.d = don't know",
  "own_edu6",          "EDCAT6",        "EDCAT6_TC1",     "own highest qualification, 6-category scheme (CY2 trend-coded to CY1)",
  "numeracy_pv",       "PVNUM1:10",     "PVNUM1:10",      "numeracy proficiency, 10 plausible values (0-500)",
  "literacy_pv",       "PVLIT1:10",     "PVLIT1:10",      "literacy proficiency, 10 plausible values (0-500)",
  "occ_isco1",         "ISCO1C",        "ISCO1C",         "occupation, ISCO-08 1-digit (4-digit suppressed in CY2 PUF)",
  "occ_skill",         "ISCOSKIL4",     "ISCOSKIL4",      "occupational skill level, 4 bands",
  "earn_hr_decile",    "EARNHRDCL",     "EARNHRDCLC2",    "gross hourly earnings incl. bonus, national decile (continuous suppressed in CY2 PUF)",
  "sex",               "GENDER_R",      "GENDER_R",       "1 male, 2 female",
  "age10",             "AGEG10LFS",     "AGEG10LFS",      "age band, 10-year groups (1=16-25 ... 5=56-65)",
  "region_tl2",        "REG_TL2",       "REG_TL2",        "OECD TL2 region; CY1 = England UKC-UKK + N.Ireland UKN; CY2 = England only",
  "final_weight",      "SPFWT0",        "SPFWT0",         "final sample weight"
)

# ---- coded value schemes (sourced from SPSS value labels in 02_harmonise) -----
# Origin (parental education) -> 3 ordered bands.
PARED_LEVELS <- c("1" = "Low (neither parent above lower secondary)",
                  "2" = "Medium (at least one parent upper secondary / post-secondary)",
                  "3" = "High (at least one parent tertiary)")
# Own education collapsed to the same 3-band origin/destination ladder so the
# "same qualification" comparison is on a like-for-like scale. Mapping of the
# 6-category own-education variable to {low, medium, high} is set in 02_harmonise
# from the authoritative SPSS labels and recorded in the ontology scheme.

ENGLAND_TL2 <- c("UKC","UKD","UKE","UKF","UKG","UKH","UKI","UKJ","UKK")
NIRELAND_TL2 <- "UKN"

ACCESS_DATE <- "2026-06-17"   # date the public-use files were downloaded
