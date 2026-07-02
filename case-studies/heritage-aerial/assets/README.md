# Shareable assets — NAPH / real NCAP data

Images generated from the live case study for LinkedIn and the Tesseract site.
All are real-data-backed (292 frames from the public NCAP Air Photo Finder API,
harvested 2 Jul 2026). Draft captions below — edit to taste. No em dashes per house style.

| File | Use | Draft caption |
|---|---|---|
| `before-after.png` | Lead explainer | "One real NCAP frame, from digitised to computable. The raw Air Photo Finder API already gives you a footprint and an ISO date; NAPH turns it into queryable linked data with a stable URI, WGS84 geometry, machine-readable rights and IIIF/STAC exports. 292 frames, 0 SHACL violations." |
| `measured-coverage.png` | Data / proof | "We stopped guessing and measured. 300 real records from NCAP's public API: 100% already carry a machine-readable footprint, 100% an ISO-8601 date with a precision flag, 100% a stable ID. The only genuine Baseline gap is machine-readable rights. Computation-readiness for historic aerial photography is closer than people assume." |
| `stack.png` | Positioning | "The gap nobody had filled: a crosswalk binding the archival stack (Records in Contexts, PROV-O) to the geospatial/imagery stack (STAC, GeoSPARQL, IIIF) for historic aerial photography. NAPH is that bridge, wrapped in FAIR and CARE, across three incrementally-adoptable tiers." |
| `real-demo-world.png` | Hero / scope | "292 real NCAP frames, harvested live and auto-lifted to a computation-ready standard. Hong Kong 1924 to the Caribbean, 1924 to 1956, every one queryable by space and time. Open source." |
| `real-demo-europe.png` | Detail view | "Every frame becomes a full linked-data record: sortie, ISO date, WGS84 footprint, perspective, camera, collection context and a link back to the source. Click any footprint." |

## Regenerate

```bash
# real map assets (serve the case study, then screenshot demo/real.html)
python3 -m http.server 8799 &
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new \
  --window-size=1680,1000 --virtual-time-budget=9000 \
  --screenshot=assets/real-demo-world.png http://localhost:8799/demo/real.html
```

The explainer cards (`before-after`, `measured-coverage`, `stack`) are built from
standalone HTML; regenerate by re-screenshotting those pages at
`--force-device-scale-factor=2`.
