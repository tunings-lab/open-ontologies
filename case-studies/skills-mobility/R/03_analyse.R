#!/usr/bin/env Rscript
# 03_analyse.R -- the analysis. Everything uses the final weight for point
# estimates, the 80 replicate weights for standard errors, and the 10 plausible
# values combined by Rubin's rules. All estimates are descriptive associations
# with 95% confidence intervals; nothing here is a causal claim.
#
# Outputs (outputs/tables/*.csv and outputs/derived results.rds):
#   1. numeracy / literacy mean by parental-education band, each cycle (gradient)
#   2. share reaching tertiary qualification by parental-education band
#   3. origin gap (High vs Low) in numeracy, adjusted for age and sex
#   4. "same qualification, different origin": origin gap net of own qualification
#   5. within-qualification origin gap (for the headline figure)
#   6. nested models: does numeracy predict earnings / occupation BEYOND quals
#   7. breakdowns by sex and (CY1 England) region

source("config.R"); source("R/lib_piaac.R")
suppressMessages({library(dplyr); library(tidyr); library(purrr); library(survey)})

cy1 <- readRDS(file.path(DERIV_DIR, "piaac_cy1.rds"))
cy2 <- readRDS(file.path(DERIV_DIR, "piaac_cy2.rds"))
# England-only subsets so 2012 and 2023 are on the same geography
cy1e <- cy1[cy1$england, ]
cy2e <- cy2[cy2$england, ]

# weighted grand SD of numeracy (pool 10 PVs) -> standardise for predictor models
grand_sd <- function(d, pv) {
  stk <- map_dfr(pv, ~tibble(x = d[[.x]], w = d$SPFWT0))
  stk <- stk[!is.na(stk$x), ]
  m <- weighted.mean(stk$x, stk$w); sqrt(weighted.mean((stk$x - m)^2, stk$w))
}

res <- list()

# ===== 1. proficiency gradient by parental education ==========================
gradient <- function(d, cyc) {
  des <- piaac_design(d[!is.na(d$origin), ])
  bind_rows(
    piaac_mean_pv(des, PV_NUM, ~origin) %>% mutate(domain = "Numeracy"),
    piaac_mean_pv(des, PV_LIT, ~origin) %>% mutate(domain = "Literacy")
  ) %>% mutate(cycle = cyc) %>%
    rename(origin = group) %>%
    mutate(origin = factor(origin, levels = c("Low","Medium","High")))
}
res$gradient <- bind_rows(gradient(cy1e, "2012"), gradient(cy2e, "2023"))
write.csv(res$gradient, file.path(OUT_TAB, "01_proficiency_gradient.csv"), row.names = FALSE)

# ===== 2. share reaching tertiary qualification by origin =====================
tertiary_by_origin <- function(d, cyc) {
  d2 <- d[!is.na(d$origin) & !is.na(d$own_edu), ]
  d2$tertiary <- as.integer(d2$own_edu == "High")
  des <- piaac_design(d2)
  sb <- svyby(~tertiary, ~origin, des, svymean, na.rm = TRUE, vartype = "se")
  tibble(cycle = cyc, origin = factor(as.character(sb$origin), levels=c("Low","Medium","High")),
         pct = 100*sb$tertiary, se = 100*sb$se,
         ci_lo = pct - 1.96*se, ci_hi = pct + 1.96*se)
}
res$tertiary <- bind_rows(tertiary_by_origin(cy1e,"2012"), tertiary_by_origin(cy2e,"2023"))
write.csv(res$tertiary, file.path(OUT_TAB, "02_tertiary_by_origin.csv"), row.names = FALSE)

# ===== 3 & 4. origin gap in numeracy: total vs net of own qualification =======
# Total gap: numeracy ~ origin + sex + age   (adjusts only composition)
# Net gap:   numeracy ~ origin + own_edu + sex + age  (holds qualification fixed)
origin_gap_models <- function(d, cyc) {
  d2 <- d[!is.na(d$origin) & !is.na(d$own_edu) & !is.na(d$sex), ]
  des <- piaac_design(d2)
  total <- piaac_mi_glm(function(i)
    svyglm(as.formula(paste0(PV_NUM[i], " ~ origin + sex + age_band")), design = des))
  net <- piaac_mi_glm(function(i)
    svyglm(as.formula(paste0(PV_NUM[i], " ~ origin + own_edu + sex + age_band")), design = des))
  bind_rows(
    total %>% filter(term %in% c("originMedium","originHigh")) %>% mutate(model="Total (composition-adjusted)"),
    net   %>% filter(term %in% c("originMedium","originHigh")) %>% mutate(model="Net of own qualification")
  ) %>% mutate(cycle = cyc)
}
res$origin_gap <- bind_rows(origin_gap_models(cy1e,"2012"), origin_gap_models(cy2e,"2023"))
write.csv(res$origin_gap, file.path(OUT_TAB, "03_origin_gap_numeracy.csv"), row.names = FALSE)

# ===== 5. within-qualification origin gap (High vs Low), for the figure =======
within_qual_gap <- function(d, cyc) {
  d <- d[!is.na(d$origin) & !is.na(d$own_edu) & !is.na(d$sex), ]
  map_dfr(levels(d$own_edu), function(lvl) {
    s <- d[d$own_edu == lvl & d$origin %in% c("Low","High"), ]
    s$origin <- droplevels(factor(s$origin, levels = c("Low","High")))
    if (nlevels(s$origin) < 2 || nrow(s) < 60) return(NULL)
    des <- piaac_design(s)
    g <- piaac_mi_glm(function(i)
      svyglm(as.formula(paste0(PV_NUM[i], " ~ origin + sex + age_band")), design = des)) %>%
      filter(term == "originHigh")
    mutate(g, own_edu = lvl, n = nrow(s), cycle = cyc)
  })
}
res$within_qual <- bind_rows(within_qual_gap(cy1e,"2012"), within_qual_gap(cy2e,"2023"))
write.csv(res$within_qual, file.path(OUT_TAB, "05_within_qualification_gap.csv"), row.names = FALSE)

# ===== 6. nested models: numeracy beyond qualification ========================
# CY1 (full occupation + validated earnings decile). Standardise numeracy per SD.
sdc <- grand_sd(cy1, PV_NUM)
nested <- function(d, outcome, family, cyc, sd_const) {
  keep <- c("origin","own_edu","sex","age_band", outcome)
  d2 <- d[complete.cases(d[, keep]) & !is.na(d[[PV_NUM[1]]]), ]
  des <- piaac_design(d2)
  # model A: qualification + controls ; model B: + numeracy (per SD)
  fit <- function(i, withnum) {
    d2$.num <- (d2[[PV_NUM[i]]] - weighted.mean(d2[[PV_NUM[i]]], d2$SPFWT0)) / sd_const
    des_i <- update(des, .num = (get(PV_NUM[i]) - weighted.mean(get(PV_NUM[i]), SPFWT0))/sd_const)
    rhs <- if (withnum) "own_edu + .num + sex + age_band" else "own_edu + sex + age_band"
    svyglm(as.formula(paste0(outcome, " ~ ", rhs)), design = des_i, family = family)
  }
  coefB <- piaac_mi_glm(function(i) fit(i, TRUE))
  # weighted R2 (linear) or McFadden pseudo-R2 (binomial), averaged across PVs
  r2 <- function(withnum) mean(map_dbl(1:10, function(i) {
    f <- fit(i, withnum)
    if (identical(family, gaussian())) wtd_r2(f) else {
      f0 <- svyglm(as.formula(paste0(outcome, " ~ 1")), design = des, family = family)
      as.numeric(1 - (f$deviance/2) / (f0$deviance/2))   # McFadden pseudo-R2
    }
  }))
  list(coef = mutate(coefB, outcome = outcome, cycle = cyc),
       r2A = r2(FALSE), r2B = r2(TRUE))
}
earn_m <- nested(cy1, "earn_decile", gaussian(), "2012", sdc)
occ_m  <- nested(cy1, "occ_high",   quasibinomial(), "2012", sdc)
res$nested_coef <- bind_rows(earn_m$coef, occ_m$coef) %>% filter(term == ".num")
res$nested_r2 <- tibble(
  outcome = c("earn_decile","occ_high"),
  family  = c("linear R2","McFadden pseudo-R2"),
  r2_quals_only = c(earn_m$r2A, occ_m$r2A),
  r2_plus_numeracy = c(earn_m$r2B, occ_m$r2B),
  delta = r2_plus_numeracy - r2_quals_only)
write.csv(res$nested_coef, file.path(OUT_TAB, "06_nested_numeracy_coef.csv"), row.names = FALSE)
write.csv(res$nested_r2,   file.path(OUT_TAB, "06_nested_r2.csv"), row.names = FALSE)

# ===== 7. breakdowns: origin gap by sex; by CY1 England region ================
gap_by_sex <- function(d, cyc) {
  d <- d[!is.na(d$origin) & d$origin %in% c("Low","High") & !is.na(d$sex), ]
  map_dfr(c("Male","Female"), function(sx) {
    s <- d[d$sex == sx, ]; s$origin <- droplevels(factor(s$origin, levels=c("Low","High")))
    des <- piaac_design(s)
    piaac_mi_glm(function(i) svyglm(as.formula(paste0(PV_NUM[i]," ~ origin + age_band")), design=des)) %>%
      filter(term=="originHigh") %>% mutate(sex = sx, cycle = cyc, n = nrow(s))
  })
}
res$gap_sex <- bind_rows(gap_by_sex(cy1e,"2012"), gap_by_sex(cy2e,"2023"))
write.csv(res$gap_sex, file.path(OUT_TAB, "07_origin_gap_by_sex.csv"), row.names = FALSE)

saveRDS(res, file.path(DERIV_DIR, "results.rds"))

# ---- console headline summary ------------------------------------------------
cat("\n================ HEADLINE NUMBERS ================\n")
cat("\n[1] Numeracy mean by parental education (England):\n")
print(res$gradient %>% filter(domain=="Numeracy") %>%
        transmute(cycle, origin, mean=round(estimate,1), ci=sprintf("[%.1f, %.1f]",ci_lo,ci_hi)) %>% as.data.frame())
cat("\n[2] % reaching tertiary by origin:\n")
print(res$tertiary %>% transmute(cycle,origin,pct=round(pct,1),ci=sprintf("[%.1f, %.1f]",ci_lo,ci_hi)) %>% as.data.frame())
cat("\n[3/4] Origin High-vs-Low numeracy gap, total vs net of qualification:\n")
print(res$origin_gap %>% filter(term=="originHigh") %>%
        transmute(cycle,model,gap=round(estimate,1),ci=sprintf("[%.1f, %.1f]",ci_lo,ci_hi)) %>% as.data.frame())
cat("\n[6] Numeracy (per SD) coefficient beyond qualifications, and Delta-R2:\n")
print(res$nested_coef %>% transmute(outcome, coef=round(estimate,3), ci=sprintf("[%.3f, %.3f]",ci_lo,ci_hi)) %>% as.data.frame())
print(as.data.frame(res$nested_r2 %>% mutate(across(where(is.numeric), ~round(.,3)))))
cat("\n03_analyse.R complete.\n")
