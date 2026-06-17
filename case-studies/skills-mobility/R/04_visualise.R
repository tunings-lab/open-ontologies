#!/usr/bin/env Rscript
# 04_visualise.R -- accessible figures (Okabe-Ito colourblind-safe palette,
# large type, direct labels, descriptive captions that double as alt text).
# Each figure is saved as a high-resolution PNG and as the underlying CSV.

source("config.R"); source("R/lib_piaac.R")
suppressMessages({library(ggplot2); library(dplyr); library(tidyr); library(scales)})

res  <- readRDS(file.path(DERIV_DIR, "results.rds"))
cy1  <- readRDS(file.path(DERIV_DIR, "piaac_cy1.rds")); cy1e <- cy1[cy1$england, ]

# Okabe-Ito (colourblind-safe)
OI <- c(orange="#E69F00", sky="#56B4E9", green="#009E73", blue="#0072B2",
        vermillion="#D55E00", grey="#999999")
ORIGIN_COL <- c(Low = OI[["orange"]], Medium = OI[["sky"]], High = OI[["green"]])
base_theme <- theme_minimal(base_size = 15) +
  theme(panel.grid.minor = element_blank(),
        plot.title = element_text(face = "bold", size = 17),
        plot.caption = element_text(size = 10, colour = "grey30", hjust = 0),
        legend.position = "top")
save_fig <- function(p, name, w = 10, h = 6) {
  ggsave(file.path(OUT_FIG, paste0(name, ".png")), p, width = w, height = h, dpi = 150, bg = "white")
}

# ===== Figure 1: parental-education skills gradient ===========================
g1 <- res$gradient %>% filter(domain == "Numeracy") %>%
  mutate(origin = factor(origin, levels = c("Low","Medium","High")), cycle = factor(cycle))
write.csv(g1, file.path(OUT_FIG, "fig1_gradient.csv"), row.names = FALSE)
p1 <- ggplot(g1, aes(origin, estimate, fill = origin)) +
  geom_col(width = .7) +
  geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = .2, linewidth = .6) +
  geom_text(aes(y = ci_hi, label = round(estimate)), vjust = -0.8, size = 4.4) +
  facet_wrap(~cycle) +
  scale_fill_manual(values = ORIGIN_COL, guide = "none") +
  coord_cartesian(ylim = c(200, 318)) +
  labs(title = "Adults' numeracy rises steeply with their parents' education",
       subtitle = "Mean PIAAC numeracy score (0-500) by parental education, England",
       x = "Parental education (origin)", y = "Mean numeracy score",
       caption = paste0("Bars show mean numeracy with 95% confidence intervals. In both 2012 and 2023, adults whose parents\n",
                        "attained tertiary education score about 50 points (roughly one standard deviation) above those whose\n",
                        "parents did not finish upper secondary. Source: OECD PIAAC public-use files, England.")) +
  base_theme
save_fig(p1, "fig1_gradient")

# ===== Figure 2: same qualification, different origin (the headline) ==========
# Mean numeracy by own qualification x origin (Low vs High origin), CY1 England.
d2 <- cy1e[!is.na(cy1e$own_edu) & cy1e$origin %in% c("Low","High"), ]
d2$origin <- droplevels(factor(d2$origin, levels = c("Low","High")))
des2 <- piaac_design(d2)
d2$grp <- interaction(d2$own_edu, d2$origin, sep = "||")
des2g <- piaac_design(d2)
m2 <- piaac_mean_pv(des2g, PV_NUM, ~grp) %>%
  separate(group, into = c("own_edu","origin"), sep = "\\|\\|") %>%
  mutate(own_edu = factor(own_edu, levels = c("Low","Medium","High")),
         origin  = factor(origin,  levels = c("Low","High")))
write.csv(m2, file.path(OUT_FIG, "fig2_same_qualification.csv"), row.names = FALSE)
p2 <- ggplot(m2, aes(own_edu, estimate, colour = origin, group = origin)) +
  geom_line(linewidth = 1, position = position_dodge(.25)) +
  geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi), width = .15, linewidth = .7,
                position = position_dodge(.25)) +
  geom_point(size = 3.4, position = position_dodge(.25)) +
  scale_colour_manual(values = c(Low = OI[["orange"]], High = OI[["green"]]),
                      name = "Parental education (origin)") +
  labs(title = "The origin gap survives at every qualification level",
       subtitle = "Mean numeracy by the adult's own highest qualification and parental education. England, 2012",
       x = "Adult's own highest qualification", y = "Mean numeracy score",
       caption = paste0("Among adults holding the SAME qualification, those from a high-education background still score about\n",
                        "37 points higher within the upper-secondary and tertiary groups. Qualifications alone understate the\n",
                        "origin gap. Lines join Low-origin and High-origin means; bars are 95% confidence intervals.")) +
  base_theme
save_fig(p2, "fig2_same_qualification")

# ===== Figure 3: numeracy adds predictive power beyond qualifications =========
g3 <- res$nested_r2 %>%
  transmute(outcome = recode(outcome, earn_decile = "Hourly earnings (decile)",
                             occ_high = "Professional / managerial job"),
            `Qualifications + age + sex` = r2_quals_only,
            `... plus numeracy` = r2_plus_numeracy) %>%
  pivot_longer(-outcome, names_to = "model", values_to = "r2") %>%
  mutate(model = factor(model, levels = c("Qualifications + age + sex", "... plus numeracy")))
write.csv(g3, file.path(OUT_FIG, "fig3_numeracy_beyond_quals.csv"), row.names = FALSE)
p3 <- ggplot(g3, aes(outcome, r2, fill = model)) +
  geom_col(position = position_dodge(.7), width = .6) +
  geom_text(aes(label = percent(r2, accuracy = 0.1)),
            position = position_dodge(.7), vjust = -0.6, size = 4) +
  scale_fill_manual(values = c(OI[["grey"]], OI[["blue"]]), name = NULL) +
  scale_y_continuous(labels = percent_format(accuracy = 1), expand = expansion(mult = c(0,.15))) +
  labs(title = "Numeracy explains outcomes beyond formal qualifications",
       subtitle = "Variance explained (R-squared) before and after adding numeracy, England 2012",
       x = NULL, y = "Share of variance explained",
       caption = paste0("Adding numeracy to a model that already contains the adult's qualification, age and sex raises the\n",
                        "variance explained in earnings from 30.5% to 36.7%, and in occupational attainment from 16.0% to 20.7%.\n",
                        "Skills carry information that qualifications do not. Source: OECD PIAAC public-use file, England 2012.")) +
  base_theme
save_fig(p3, "fig3_numeracy_beyond_quals")

# ===== Figure 4: educational mobility -- tertiary attainment by origin ========
g4 <- res$tertiary %>% mutate(origin = factor(origin, levels = c("Low","Medium","High")))
write.csv(g4, file.path(OUT_FIG, "fig4_tertiary_by_origin.csv"), row.names = FALSE)
p4 <- ggplot(g4, aes(origin, pct/100, fill = origin)) +
  geom_col(width = .7) +
  geom_errorbar(aes(ymin = ci_lo/100, ymax = ci_hi/100), width = .2, linewidth = .6) +
  geom_text(aes(y = ci_hi/100, label = percent(pct/100, accuracy = 1)), vjust = -0.7, size = 4.2) +
  facet_wrap(~cycle) +
  scale_fill_manual(values = ORIGIN_COL, guide = "none") +
  scale_y_continuous(labels = percent_format(accuracy = 1), limits = c(0, .85)) +
  labs(title = "Reaching a degree still depends heavily on where you started",
       subtitle = "Share of adults attaining a tertiary qualification, by parental education, England",
       x = "Parental education (origin)", y = "Attained tertiary qualification",
       caption = paste0("In 2023, 60% of adults from a high-education background hold a tertiary qualification, against 32% from a\n",
                        "low-education background. The gap narrowed since 2012 (62% vs 23%) as attainment among low-origin adults\n",
                        "rose. Bars are 95% confidence intervals. Source: OECD PIAAC public-use files, England.")) +
  base_theme
save_fig(p4, "fig4_tertiary_by_origin")

message("04_visualise.R complete. Figures + CSVs in outputs/figures/.")
print(list.files(OUT_FIG, pattern = "png$"))
