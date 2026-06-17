# lib_piaac.R -- estimation helpers that handle PIAAC correctly:
#   * point estimates use the final weight SPFWT0;
#   * sampling variance uses the 80 jackknife replicate weights with the OECD
#     formula Var = sum_r (theta_r - theta_0)^2 (survey type="other", mse=TRUE);
#   * proficiency uses the 10 plausible values, combined by Rubin's rules.
# These are the rules in the OECD "Survey of Adult Skills (PIAAC) Data Analysis
# Manual". Naive standard errors and single-PV averages are NOT used anywhere.

suppressWarnings(suppressMessages({
  library(survey); library(mitools); library(dplyr); library(tidyr); library(purrr)
}))
options(survey.lonely.psu = "adjust")

# ---- read one cycle, keeping only the columns we need ------------------------
piaac_read <- function(cycle) {
  s <- SOURCES[SOURCES$cycle == cycle, ]
  path <- file.path(RAW_DIR, s$file)
  vm   <- VARMAP[[tolower(cycle)]]
  cols <- c(VARMAP[[tolower(cycle)]], W_FINAL, W_REP, PV_NUM, PV_LIT)
  cols <- unique(cols[!grepl(":", cols)])      # drop the "PVNUM1:10" shorthand rows
  # readr: read everything as character first (PIAAC mixes letter missing codes
  # into otherwise numeric columns), then coerce deliberately.
  raw <- readr::read_delim(path, delim = s$delim, col_types = readr::cols(.default = "c"),
                           progress = FALSE, show_col_types = FALSE)
  keep <- intersect(cols, names(raw))
  raw[keep]
}

# coerce a character vector to numeric, turning PIAAC letter/dot missing codes to NA
num <- function(x) suppressWarnings(as.numeric(x))

# ---- build a PIAAC replicate-weight survey design ----------------------------
# combined.weights = TRUE because SPFWT1..80 are full replicate weights.
# The variance method differs by cycle (OECD Data Analysis Manuals):
#   Cycle 1 (2012): jackknife, Var = sum_r (theta_r - theta_0)^2
#                   -> type "other", scale 1, rscales 1.
#   Cycle 2 (2023): Fay's BRR with Fay factor 0.5,
#                   Var = 1/(R(1-0.5)^2) * sum_r (theta_r - theta_0)^2
#                   -> type "Fay", rho 0.5.
# The method is inferred from the data's `cycle` column, verified empirically
# against the published England toplines (see technical note, validation step).
piaac_design <- function(df, method = NULL) {
  if (is.null(method)) method <- if (!is.null(df$cycle) && df$cycle[1] == "CY2") "fay" else "jk"
  if (method == "fay") {
    svrepdesign(data = df, weights = ~SPFWT0, repweights = df[, W_REP],
                type = "Fay", rho = 0.5, combined.weights = TRUE, mse = TRUE)
  } else {
    svrepdesign(data = df, weights = ~SPFWT0, repweights = df[, W_REP],
                type = "other", scale = 1, rscales = rep(1, N_REP),
                combined.weights = TRUE, mse = TRUE)
  }
}

# ---- Rubin's rules across plausible values -----------------------------------
# ests: numeric vector of point estimates (one per PV)
# vars: numeric vector of sampling variances (one per PV)
rubin <- function(ests, vars) {
  m  <- length(ests)
  Q  <- mean(ests)
  Ub <- mean(vars)                  # within-imputation (sampling) variance
  B  <- if (m > 1) var(ests) else 0 # between-imputation variance
  Tt <- Ub + (1 + 1 / m) * B
  se <- sqrt(Tt)
  c(estimate = Q, se = se, ci_lo = Q - 1.96 * se, ci_hi = Q + 1.96 * se,
    within = Ub, between = B)
}

# ---- mean proficiency by group, PVs + replicate weights ----------------------
# design: a piaac_design; pv: character vector of 10 PV column names; by: a
# one-sided formula e.g. ~parental_edu (or NULL for overall mean).
piaac_mean_pv <- function(design, pv, by = NULL) {
  per_pv <- map(pv, function(v) {
    f <- as.formula(paste0("~", v))
    if (is.null(by)) {
      est <- svymean(f, design, na.rm = TRUE)
      tibble(group = "all", est = as.numeric(est), var = as.numeric(SE(est))^2)
    } else {
      sb <- svyby(f, by, design, svymean, na.rm = TRUE, vartype = "se")
      tibble(group = as.character(sb[[1]]), est = sb[[2]], var = sb[["se"]]^2)
    }
  })
  long <- bind_rows(per_pv, .id = "pv")
  long %>% group_by(group) %>%
    summarise(r = list(rubin(est, var)), .groups = "drop") %>%
    mutate(stat = map(r, ~as_tibble(as.list(.x)))) %>%
    select(group, stat) %>% unnest(stat)
}

# ---- regression combining PVs (PV as outcome OR predictor) -------------------
# fit_one(i): function returning a fitted svyglm for plausible value i.
# Returns a tidy tibble (term, estimate, se, ci_lo, ci_hi, p) with Rubin's
# rules applied via mitools::MIcombine over the 10 fits.
piaac_mi_glm <- function(fit_one, n_pv = 10) {
  fits <- lapply(seq_len(n_pv), fit_one)
  mc   <- mitools::MIcombine(results = lapply(fits, coef),
                             variances = lapply(fits, vcov))
  est  <- coef(mc); se <- sqrt(diag(vcov(mc)))
  tibble(term = names(est), estimate = as.numeric(est), se = as.numeric(se),
         ci_lo = est - 1.96 * se, ci_hi = est + 1.96 * se,
         p = 2 * pnorm(-abs(est / se)))
}

# weighted R^2 (final weight only) for a gaussian svyglm fit, used to quantify
# the predictive gain of one model over another. Averaged across PVs by caller.
wtd_r2 <- function(fit) {
  y <- model.response(model.frame(fit)); w <- weights(fit, "sampling")
  if (is.null(w)) w <- rep(1, length(y))
  mu <- weighted.mean(y, w)
  sse <- sum(w * (y - fitted(fit))^2); sst <- sum(w * (y - mu)^2)
  1 - sse / sst
}
