#!/usr/bin/env Rscript
# ontology/build_scheme.R -- generate the coded, machine-readable variable
# scheme for the analysis as a SKOS concept scheme. This is the open-ontologies
# "harmonisation layer": it turns the messy PIAAC source variables (different
# names and codings across the 2012 and 2023 files) into one documented,
# coded scheme on a common 3-band ladder. Every concept traces to a PIAAC
# source variable, its OECD value label, and the source file URL. No entity is
# invented. Outputs SKOS Turtle + JSON-LD + an entity-list CSV; the engine step
# (validate_scheme.py) then loads it into Oxigraph and writes the coverage report.

source("config.R")
suppressMessages(library(jsonlite))

hmap <- read.csv(file.path(OUT_TAB, "harmonisation_map.csv"), stringsAsFactors = FALSE)
BASE <- "https://gov.tesseract.academy/ns/skills-mobility"
src_url <- function(cy) SOURCES$url[SOURCES$cycle == cy]

# ---- variable-level concepts (top concepts) ----------------------------------
vars <- VARMAP[!grepl(":", VARMAP$cy1) | VARMAP$concept %in% c("numeracy_pv","literacy_pv"), ]
# label/definition per analysis variable
VARDEF <- c(
  parental_edu = "Origin: highest education attained by either parent, 3 bands (the social-origin measure).",
  own_edu6     = "Destination: respondent's own highest qualification, 6-category scheme collapsed to 3 bands.",
  numeracy_pv  = "Destination: numeracy proficiency (0-500), 10 plausible values.",
  literacy_pv  = "Destination: literacy proficiency (0-500), 10 plausible values.",
  occ_isco1    = "Destination: occupation, ISCO-08 major group (1-digit).",
  occ_skill    = "Destination: occupational skill level, 4 bands.",
  earn_hr_decile = "Destination: gross hourly earnings, national decile (1 = lowest, 10 = highest).",
  sex = "Analytical control: sex.", age10 = "Analytical control: age band (10-year).",
  region_tl2 = "Analytical control / breakdown: OECD TL2 region.",
  final_weight = "Final sample weight (point estimates)."
)
concept_id <- function(x) gsub("[^A-Za-z0-9]", "-", x)

# ---- build Turtle ------------------------------------------------------------
ttl <- c(
  "@prefix skos: <http://www.w3.org/2004/02/skos/core#> .",
  "@prefix dct:  <http://purl.org/dc/terms/> .",
  "@prefix prov: <http://www.w3.org/ns/prov#> .",
  "@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .",
  paste0("@prefix sm:   <", BASE, "#> ."),
  "",
  paste0("sm:scheme a skos:ConceptScheme ;"),
  '  dct:title "PIAAC educational and skills mobility variable scheme" ;',
  '  dct:description "Coded harmonisation of the OECD PIAAC public-use variables used in the Tesseract Academy intergenerational educational and skills mobility case study, across Cycle 1 (2012) and Cycle 2 (2023)." ;',
  paste0('  dct:source <', PIAAC_BASE, '> ;'),
  paste0('  dct:created "', ACCESS_DATE, '"^^<http://www.w3.org/2001/XMLSchema#date> .'),
  ""
)
esc <- function(s) gsub('"', '\\\\"', s)
entities <- list()

emit_concept <- function(id, label, definition, broader = NULL,
                         notation_cy1 = NA, notation_cy2 = NA, src = NULL, top = FALSE) {
  lines <- c(paste0("sm:", id, " a skos:Concept ;"),
             paste0('  skos:prefLabel "', esc(label), '" ;'),
             paste0('  skos:definition "', esc(definition), '" ;'),
             "  skos:inScheme sm:scheme ;")
  if (top) lines <- c(lines, "  skos:topConceptOf sm:scheme ;")
  if (!is.null(broader)) lines <- c(lines, paste0("  skos:broader sm:", broader, " ;"))
  if (!is.na(notation_cy1)) lines <- c(lines, paste0('  skos:notation "', notation_cy1, '" ;  # PIAAC 2012 source'))
  if (!is.na(notation_cy2)) lines <- c(lines, paste0('  skos:notation "', notation_cy2, '" ;  # PIAAC 2023 source'))
  if (!is.null(src)) for (u in src) lines <- c(lines, paste0("  prov:wasDerivedFrom <", u, "> ;"))
  lines[length(lines)] <- sub(" ;$", " .", lines[length(lines)])  # close
  entities[[length(entities) + 1]] <<- data.frame(
    id = id, type = if (is.null(broader)) "variable" else "coded_value",
    prefLabel = label, broader = broader %||% "", notation_cy1 = notation_cy1 %||% "",
    notation_cy2 = notation_cy2 %||% "", definition = definition,
    source = paste(src, collapse = "; "), stringsAsFactors = FALSE)
  c(lines, "")
}

# variable concepts
for (i in seq_len(nrow(vars))) {
  v <- vars[i, ]
  ttl <- c(ttl, emit_concept(
    id = concept_id(v$concept), label = v$concept, definition = VARDEF[[v$concept]] %||% v$note,
    notation_cy1 = v$cy1, notation_cy2 = v$cy2,
    src = c(src_url("CY1"), src_url("CY2")), top = TRUE))
}
# coded-value concepts (from the harmonisation map)
for (i in seq_len(nrow(hmap))) {
  r <- hmap[i, ]
  vid <- switch(r$variable, origin = "parental_edu", own_edu = "own_edu6",
                occ_skill_rank = "occ_skill", r$variable)
  cid <- concept_id(paste0(r$variable, "-", r$code))
  ttl <- c(ttl, emit_concept(
    id = cid, label = paste0(r$variable, " = ", r$band, " (code ", r$code, ")"),
    definition = r$definition, broader = concept_id(vid),
    notation_cy1 = r$source_cy1, notation_cy2 = r$source_cy2,
    src = c(src_url("CY1"), src_url("CY2"))))
}
writeLines(ttl, file.path(ONTO_DIR, "skills-mobility-scheme.ttl"))

# ---- entity-list CSV ---------------------------------------------------------
ent <- do.call(rbind, entities)
write.csv(ent, file.path(ONTO_DIR, "entities.csv"), row.names = FALSE)

# ---- JSON-LD (compact SKOS graph) --------------------------------------------
ctx <- list(skos = "http://www.w3.org/2004/02/skos/core#",
            dct = "http://purl.org/dc/terms/", prov = "http://www.w3.org/ns/prov#",
            sm = paste0(BASE, "#"),
            prefLabel = "skos:prefLabel", definition = "skos:definition",
            broader = list("@id" = "skos:broader", "@type" = "@id"),
            notation = "skos:notation",
            wasDerivedFrom = list("@id" = "prov:wasDerivedFrom", "@type" = "@id"))
graph <- lapply(seq_len(nrow(ent)), function(i) {
  r <- ent[i, ]
  obj <- list("@id" = paste0("sm:", r$id),
              "@type" = "skos:Concept",
              prefLabel = r$prefLabel, definition = r$definition,
              notation = unique(Filter(nzchar, c(r$notation_cy1, r$notation_cy2))),
              wasDerivedFrom = strsplit(r$source, "; ")[[1]])
  if (nzchar(r$broader)) obj$broader <- paste0("sm:", r$broader)
  obj
})
jsonld <- list("@context" = ctx,
               "@graph" = c(list(list("@id" = "sm:scheme", "@type" = "skos:ConceptScheme",
                                      "dct:title" = "PIAAC educational and skills mobility variable scheme")),
                            graph))
write_json(jsonld, file.path(ONTO_DIR, "skills-mobility-scheme.jsonld"),
           auto_unbox = TRUE, pretty = TRUE)

message(sprintf("Scheme built: %d concepts (%d variables, %d coded values).",
                nrow(ent), sum(ent$type=="variable"), sum(ent$type=="coded_value")))
`%||%` <- function(a,b) if (is.null(a)) b else a
