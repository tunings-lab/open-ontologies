#!/usr/bin/env Rscript
# 02_harmonise.R -- turn the two raw PIAAC public-use files into one harmonised,
# analysis-ready table with a small set of coded, documented variables on a
# common 3-band origin/destination ladder (below upper secondary / upper
# secondary / tertiary). Every recode is recorded in outputs/tables/
# harmonisation_map.csv, which is the single source of truth the ontology
# scheme (ontology/build_scheme.R) is generated from -- no entity is invented.

source("config.R")
source("R/lib_piaac.R")

# ---- coded value maps (sourced from the SPSS value labels, see technical note)
# Origin and own education share the same 3 ordered bands.
band3 <- c("1" = "Low", "2" = "Medium", "3" = "High")            # parental education
own_band <- c("1"="Low", "2"="Medium","3"="Medium",
              "4"="High","5"="High","6"="High","7"="High")        # EDCAT6 collapse
skill_rank <- c("1"=4L, "2"=3L, "3"=2L, "4"=1L)                    # ISCOSKIL4 -> higher = more skilled
BAND_LEVELS <- c("Low","Medium","High")

harmonise <- function(cycle) {
  vm  <- function(concept) VARMAP[[tolower(cycle)]][VARMAP$concept == concept]
  df  <- piaac_read(cycle)
  g   <- function(concept) df[[ vm(concept) ]]

  out <- tibble(
    cycle    = cycle,
    year     = SOURCES$year[SOURCES$cycle == cycle],
    origin   = factor(unname(band3[g("parental_edu")]), levels = BAND_LEVELS),
    own_edu  = factor(unname(own_band[g("own_edu6")]),  levels = BAND_LEVELS),
    occ_skill_rank = unname(skill_rank[g("occ_skill")]),
    isco1    = num(g("occ_isco1")),
    earn_decile = { d <- num(g("earn_hr_decile")); ifelse(d >= 1 & d <= 10, d, NA_real_) },
    sex      = factor(c("1"="Male","2"="Female")[g("sex")], levels = c("Male","Female")),
    age_band = factor(c("1"="16-24","2"="25-34","3"="35-44","4"="45-54","5"="55-65")[g("age10")],
                      levels = c("16-24","25-34","35-44","45-54","55-65")),
    region   = g("region_tl2"),
    SPFWT0   = num(df$SPFWT0)
  )
  # high-status occupation (ISCO-08 major groups 1-3: managers, professionals,
  # technicians); 0-9 are valid groups, larger codes are missing/skip.
  out$occ_high <- ifelse(out$isco1 %in% 0:9, as.integer(out$isco1 %in% 1:3), NA_integer_)
  out$england  <- out$region %in% ENGLAND_TL2
  # plausible values + replicate weights (numeric)
  for (v in c(PV_NUM, PV_LIT, W_REP)) out[[v]] <- num(df[[v]])
  # keep only working-age respondents (16-65) with a usable final weight
  out <- out[!is.na(out$age_band) & !is.na(out$SPFWT0) & out$SPFWT0 > 0, ]
  out
}

cy1 <- harmonise("CY1")
cy2 <- harmonise("CY2")

saveRDS(cy1, file.path(DERIV_DIR, "piaac_cy1.rds"))
saveRDS(cy2, file.path(DERIV_DIR, "piaac_cy2.rds"))

# ---- harmonisation map (source of truth for the ontology scheme) -------------
hmap <- bind_rows(
  tibble(variable="origin", source_cy1="PARED", source_cy2="PAREDC2",
         code=names(band3), band=unname(band3),
         definition=c("Neither parent attained upper secondary",
                      "At least one parent upper secondary / post-secondary non-tertiary",
                      "At least one parent attained tertiary")),
  tibble(variable="own_edu", source_cy1="EDCAT6", source_cy2="EDCAT6_TC1",
         code=names(own_band), band=unname(own_band),
         definition=c("Lower secondary or less (ISCED 1,2,3C short)",
                      "Upper secondary (ISCED 3A-B, C long)",
                      "Post-secondary non-tertiary (ISCED 4)",
                      "Tertiary professional (ISCED 5B)",
                      "Tertiary bachelor (ISCED 5A)",
                      "Tertiary master/research (ISCED 5A/6)",
                      "Tertiary bachelor/master/research grouped (ISCED 5A/6)")),
  tibble(variable="occ_skill_rank", source_cy1="ISCOSKIL4", source_cy2="ISCOSKIL4",
         code=names(skill_rank), band=as.character(unname(skill_rank)),
         definition=c("Skilled occupations","Semi-skilled white-collar",
                      "Semi-skilled blue-collar","Elementary occupations"))
)
write.csv(hmap, file.path(OUT_TAB, "harmonisation_map.csv"), row.names = FALSE)

# ---- sample-size / coverage summary ------------------------------------------
summ <- function(d) tibble(
  cycle = d$cycle[1], n = nrow(d),
  n_england = sum(d$england),
  n_origin = sum(!is.na(d$origin)), n_own_edu = sum(!is.na(d$own_edu)),
  n_occ = sum(!is.na(d$occ_skill_rank)), n_earn = sum(!is.na(d$earn_decile)),
  pct_origin_known = round(100 * mean(!is.na(d$origin)), 1)
)
sizes <- bind_rows(summ(cy1), summ(cy2))
write.csv(sizes, file.path(OUT_TAB, "sample_sizes.csv"), row.names = FALSE)

message("02_harmonise.R complete.")
print(as.data.frame(sizes))
cat("\nOrigin x own-education cross-tab (CY1, unweighted):\n")
print(addmargins(table(origin = cy1$origin, own = cy1$own_edu, useNA = "ifany")))
