#!/usr/bin/env Rscript
# 01_download.R -- fetch the open PIAAC public-use files (CSV + SPSS).
# Idempotent: skips files already present with a non-trivial size. Records the
# URL, byte size, md5 and access date in data/raw/MANIFEST.csv for provenance.

source("config.R")

ua <- "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124.0 Safari/537.36"

fetch <- function(url, dest) {
  if (file.exists(dest) && file.info(dest)$size > 1e6) {
    message(sprintf("  exists, skip: %s", basename(dest))); return(invisible(dest))
  }
  message(sprintf("  downloading: %s", url))
  utils::download.file(url, dest, mode = "wb", quiet = TRUE,
                       headers = c("User-Agent" = ua))
  invisible(dest)
}

manifest <- list()
message("PIAAC CSV public-use files:")
for (i in seq_len(nrow(SOURCES))) {
  s <- SOURCES[i, ]
  dest <- file.path(RAW_DIR, s$file)
  fetch(s$url, dest)
  manifest[[length(manifest) + 1]] <- data.frame(
    cycle = s$cycle, file = s$file, url = s$url,
    bytes = file.info(dest)$size, md5 = tools::md5sum(dest),
    access_date = ACCESS_DATE, stringsAsFactors = FALSE)
}

# SPSS files are optional (used only to source ontology value labels). Failure
# to fetch them is non-fatal so the CSV analysis pipeline still runs.
message("PIAAC SPSS files (for value labels; optional):")
for (i in seq_len(nrow(SOURCES_SAV))) {
  s <- SOURCES_SAV[i, ]
  dest <- file.path(RAW_DIR, s$file)
  ok <- tryCatch({ fetch(s$url, dest); TRUE }, error = function(e) {
    message(sprintf("  WARN could not fetch %s: %s", s$file, conditionMessage(e))); FALSE })
  if (ok && file.exists(dest))
    manifest[[length(manifest) + 1]] <- data.frame(
      cycle = s$cycle, file = s$file, url = s$url,
      bytes = file.info(dest)$size, md5 = tools::md5sum(dest),
      access_date = ACCESS_DATE, stringsAsFactors = FALSE)
}

man <- do.call(rbind, manifest); rownames(man) <- NULL
write.csv(man, file.path(RAW_DIR, "MANIFEST.csv"), row.names = FALSE)
message("\nManifest:"); print(man[, c("cycle","file","bytes","md5")])
message("\n01_download.R complete.")
