# Technical note: intergenerational educational and skills mobility in England (PIAAC)

This note documents the data, variables, statistical methods, validation and limitations behind the case study. It is written for analysts and official-statistics methodologists who want to check or reuse the work.

## 1. Data

| Item | Detail |
| --- | --- |
| Source | OECD Programme for the International Assessment of Adult Competencies (PIAAC), Survey of Adult Skills, public-use files |
| Files | `prggbrp1.csv` (Cycle 1, 2012, 8,892 respondents) and `prggbrp2.csv` (Cycle 2, 2023, 4,941 respondents) |
| Host | OECD public file store, `https://webfs.oecd.org/piaac/` (open directory; no registration or licence) |
| Value labels | Taken from the official SPSS public-use files (`prggbrp1.sav`, `PRGGBRP2.sav`) on the same store |
| Access date | 17 June 2026; URLs, byte sizes and MD5 checksums recorded in `data/raw/MANIFEST.csv` |
| Population | Adults aged 16 to 65 |

The UK participated in PIAAC Cycle 1 as **England and Northern Ireland** and in Cycle 2 as **England**. For every cross-cycle comparison the 2012 sample is restricted to England (OECD TL2 regions UKC to UKK, excluding Northern Ireland, UKN) so the geography matches. Northern Ireland was heavily oversampled in 2012; the final weights correct for this, and restricting to England removes it from the comparison entirely.

## 2. Variables and harmonisation

The two cycles use different variable names and, in places, different codings. All analysis variables are mapped to a common scheme, recorded in `outputs/tables/harmonisation_map.csv` and published as a coded SKOS scheme in `ontology/`.

| Concept | 2012 variable | 2023 variable | Coding used |
| --- | --- | --- | --- |
| Origin (parental education) | `PARED` | `PAREDC2` | 3 bands: Low (neither parent above lower secondary), Medium (at least one upper secondary or post-secondary non-tertiary), High (at least one tertiary). Codes 6/7/8/9 = missing |
| Own highest qualification | `EDCAT6` | `EDCAT6_TC1` | Collapsed to the same 3 bands: Low = code 1; Medium = 2,3; High = 4,5,6,7. (2012 uses code 7 for grouped tertiary; 2023 uses 5 and 6) |
| Numeracy | `PVNUM1`-`PVNUM10` | same | 10 plausible values, 0-500 |
| Literacy | `PVLIT1`-`PVLIT10` | same | 10 plausible values, 0-500 |
| Occupation (1-digit) | `ISCO1C` | `ISCO1C` | ISCO-08 major group; high-status = groups 1-3 (managers, professionals, technicians) |
| Occupational skill | `ISCOSKIL4` | `ISCOSKIL4` | 4 bands, recoded so higher = more skilled |
| Hourly earnings | `EARNHRDCL` | `EARNHRDCLC2` | National decile, 1 = lowest to 10 = highest |
| Sex | `GENDER_R` | `GENDER_R` | Male, Female |
| Age | `AGEG10LFS` | `AGEG10LFS` | 10-year bands |
| Region | `REG_TL2` | `REG_TL2` | OECD TL2 |
| Final weight | `SPFWT0` | `SPFWT0` | |
| Replicate weights | `SPFWT1`-`SPFWT80` | same | 80 replicates |

The `_TC1` suffix on the 2023 education variable denotes the OECD's own trend-coding to Cycle 1, so it is the version comparable with the 2012 `EDCAT6`.

**An empirical correction worth recording.** The SPSS value labels for the earnings-decile variable are internally inconsistent (they label code 2 as the "9th decile", code 3 as the "8th", and so on, which would make the scale non-monotonic). We did not trust the labels. We validated the variable against the continuous earnings measure available in 2012 (`EARNHRBONUSPPP`): mean continuous earnings rise monotonically from 7.6 PPP-USD per hour at decile 1 to 54.0 at decile 10, with a Spearman correlation of 0.99. The numeric values are therefore standard decile ranks (1 = lowest, 10 = highest) and the mid-range labels are a labelling error in the public file. We use the numeric values.

## 3. Statistical methods

**Plausible values.** Proficiency in PIAAC is reported as ten plausible values, not a single score. Each analysis is run separately on each of the ten values and the results are combined by Rubin's rules: the point estimate is the mean of the ten, and the total variance is the mean sampling variance plus `(1 + 1/10)` times the between-value variance. Averaging the ten plausible values into one score (a common error) understates uncertainty and is not done anywhere here.

**Replicate weights and the cycle-specific variance method.** Point estimates use the final weight `SPFWT0`. Sampling variances use the 80 replicate weights. The replication method differs by cycle, and using the wrong one inflates standard errors by a factor of roughly `sqrt(20)`:

- **Cycle 1 (2012): jackknife.** Variance is the simple sum of squared replicate deviations, `Var = sum_r (theta_r - theta_0)^2`. Implemented with `survey::svrepdesign(type = "other", scale = 1, rscales = 1, mse = TRUE)`.
- **Cycle 2 (2023): Fay's balanced repeated replication, Fay factor 0.5.** Variance is `1 / (R(1 - 0.5)^2) * sum_r (theta_r - theta_0)^2 = (1/20) * sum_r (...)`. Implemented with `survey::svrepdesign(type = "Fay", rho = 0.5, mse = TRUE)`.

We confirmed the method empirically. Computing the 2023 England mean numeracy with the jackknife formula gives a standard error of 7.25, which is implausible for a sample of about 4,900; the Fay method gives 1.65. The ratio is `sqrt(20)`, exactly the Fay scaling. The Fay estimate matches the published OECD standard error.

**Models.** All regression models are survey-weighted generalised linear models (`survey::svyglm`) fitted on the replicate-weight design, run once per plausible value and combined across the ten with `mitools::MIcombine`, so that both sampling variance and between-value variance enter the standard errors.

- *Origin gradient and gap:* mean numeracy by origin band; and `numeracy ~ origin + sex + age` (total gap) versus `numeracy ~ origin + own_qualification + sex + age` (gap net of qualification).
- *Within-qualification gap:* `numeracy ~ origin + sex + age` fitted separately within each own-qualification band.
- *Skills beyond qualifications:* `outcome ~ qualification + age + sex` versus the same plus standardised numeracy, for two outcomes (earnings decile, linear; professional/managerial occupation, quasi-binomial). Numeracy is standardised to mean 0, SD 1 using the weighted pooled plausible-value distribution, so its coefficient reads per standard deviation. Variance explained is the weighted R-squared (linear) or McFadden pseudo-R-squared (binomial), averaged across the ten plausible values.

## 4. Validation against published figures

| Quantity | This pipeline | Published OECD |
| --- | --- | --- |
| England mean numeracy, 2023 | 268.8 (SE 1.65) | 268 |
| England mean numeracy, 2012 | 261.8 (SE 1.10) | ~262 |
| Direction of change 2012 to 2023 | significant rise | significant rise |

The pipeline reproduces the published England toplines, which gives confidence that the weighting, plausible-value and variance handling are correct.

## 5. Headline estimates with confidence intervals

| Estimate (England) | 2012 | 2023 |
| --- | --- | --- |
| Numeracy, Low / Medium / High origin | 239 / 271 / 289 | 242 / 279 / 293 |
| Tertiary attainment, Low / High origin | 23% / 62% | 32% / 60% |
| Origin gap (High-Low), total | 51.9 [46.7, 57.1] | 47.3 [36.2, 58.3] |
| Origin gap (High-Low), net of own qualification | 34.5 [28.8, 40.1] | 32.4 [21.5, 43.2] |
| Within upper-secondary group, High-Low gap | 38.3 [29.2, 47.4] | 31.3 [9.9, 52.7] |
| Within tertiary group, High-Low gap | 37.0 [28.1, 45.9] | 27.3 [14.6, 40.1] |
| Numeracy coefficient (per SD) on earnings decile | 0.86 [0.73, 0.99] | not estimated (earnings suppressed) |
| Variance explained in earnings, quals only vs + numeracy | 30.5% vs 36.7% | not estimated |

Square brackets are 95% confidence intervals.

## 6. Limitations

1. **Descriptive, not causal.** These are associations. Parental education is a proxy for a bundle of family advantages; the design cannot separate them or establish causation.
2. **Cross-sectional.** PIAAC is not a panel. "Origin to destination" is reconstructed within a single survey from retrospective parental-education reporting, not followed over time.
3. **Reverse and contemporaneous influences.** Skills and qualifications are measured in adulthood and partly co-determined; the nested-model results describe shared and unique predictive content, not a causal decomposition.
4. **Public-file masking in 2023.** Continuous earnings and four-digit occupation are suppressed in the 2023 public-use file. Cross-year analyses therefore use earnings deciles and one-digit occupation. The continuous-earnings nested model is 2012 only.
5. **Missing origin data.** Parental education is unknown (don't know, refused, not stated) for about 17% of respondents, who are excluded from origin analyses. If non-response is related to origin, the gradient could be mildly under- or over-stated.
6. **Three-band collapse.** Banding parental and own education to three levels aids comparability but discards within-band detail, in particular differences within tertiary education.

## 7. Reproduce

```bash
# from the case-study directory
Rscript R/01_download.R          # fetch the open PIAAC files (idempotent)
Rscript R/02_harmonise.R         # build the harmonised analysis table
Rscript R/03_analyse.R           # estimates, with PVs + replicate weights
Rscript R/04_visualise.R         # figures + per-figure CSVs
Rscript ontology/build_scheme.R  # generate the SKOS variable scheme
.venv/bin/python ontology/validate_scheme.py   # validate via the Oxigraph engine
```

A clean run regenerates every number in the case study and this note, and every figure, from the raw open files.
