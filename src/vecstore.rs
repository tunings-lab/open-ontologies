//! In-memory vector store with dual-space search (cosine + Poincaré)
//! and SQLite persistence.

use crate::hnsw_index::{CosineIndex, PoincareIndex};
use crate::poincare::{cosine_similarity, l2_normalize, poincare_distance};
use crate::state::StateDb;
use std::collections::HashMap;

#[derive(Clone)]
struct VecEntry {
    text_vec: Vec<f32>,
    struct_vec: Vec<f32>,
}

/// Brute-force dual-space vector store with an opt-in HNSW cosine index.
pub struct VecStore {
    db: StateDb,
    entries: HashMap<String, VecEntry>,
    /// Lazily-built HNSW index over `text_vec`s for accelerated cosine
    /// search. Invalidated on every mutation; rebuilt on first
    /// `search_cosine_hnsw` after a mutation. The existing
    /// `search_cosine` linear scan is unchanged and continues to work
    /// without HNSW.
    cosine_index: Option<CosineIndex>,
    /// Lazily-built HNSW index over `struct_vec`s for accelerated Poincaré
    /// search. Same invalidation semantics as `cosine_index`. The existing
    /// brute-force `search_poincare` is unchanged.
    poincare_index: Option<PoincareIndex>,
}

impl VecStore {
    pub fn new(db: StateDb) -> Self {
        Self {
            db,
            entries: HashMap::new(),
            cosine_index: None,
            poincare_index: None,
        }
    }

    pub fn upsert(&mut self, iri: &str, text_vec: &[f32], struct_vec: &[f32]) {
        self.entries.insert(iri.to_string(), VecEntry {
            text_vec: l2_normalize(text_vec),
            struct_vec: struct_vec.to_vec(),
        });
        // Invalidate BOTH HNSW indices — instant-distance is immutable.
        self.cosine_index = None;
        self.poincare_index = None;
    }

    pub fn remove(&mut self, iri: &str) {
        self.entries.remove(iri);
        self.cosine_index = None;
        self.poincare_index = None;
    }

    pub fn search_cosine(&self, query: &[f32], top_k: usize) -> Vec<(String, f32)> {
        let query_norm = l2_normalize(query);
        let mut scores: Vec<(String, f32)> = self.entries.iter()
            .map(|(iri, e)| (iri.clone(), cosine_similarity(&query_norm, &e.text_vec)))
            .collect();
        scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
        scores.truncate(top_k);
        scores
    }

    /// HNSW-accelerated cosine search. Approximate top-k via the HNSW index;
    /// builds the index lazily on first call (and after any mutation).
    ///
    /// Same query/output semantics as [`Self::search_cosine`] (results sorted
    /// by cosine similarity descending, top_k truncation, same scale), but
    /// sub-linear query time once the index is warm. The trade-off vs the
    /// exact brute-force scan: approximate top-k under default HNSW params,
    /// rebuild cost on every mutation.
    ///
    /// Use this when:
    /// - The store has more than a few hundred entries
    /// - You expect many queries between mutations (`embed-once,
    ///   search-many-times`)
    /// - Approximate top-k is acceptable
    ///
    /// Otherwise stick with [`Self::search_cosine`].
    pub fn search_cosine_hnsw(&mut self, query: &[f32], top_k: usize) -> Vec<(String, f32)> {
        if self.entries.is_empty() {
            return Vec::new();
        }
        if self.cosine_index.is_none() {
            // Lazy build from current entries. Vectors are already L2-normalised
            // (the upsert path guarantees that), so the HNSW index sees unit
            // vectors and the cosine distance == 1 - dot product.
            let points: Vec<(String, Vec<f32>)> = self
                .entries
                .iter()
                .map(|(iri, e)| (iri.clone(), e.text_vec.clone()))
                .collect();
            self.cosine_index = Some(CosineIndex::build(points));
        }
        let query_norm = l2_normalize(query);
        match self.cosine_index.as_mut() {
            Some(idx) => idx.search(&query_norm, top_k),
            None => Vec::new(),
        }
    }

    pub fn search_poincare(&self, query: &[f32], top_k: usize) -> Vec<(String, f32)> {
        let mut scores: Vec<(String, f32)> = self.entries.iter()
            .map(|(iri, e)| (iri.clone(), poincare_distance(query, &e.struct_vec)))
            .collect();
        scores.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal));
        scores.truncate(top_k);
        scores
    }

    /// HNSW-accelerated Poincaré search. Mirrors [`Self::search_cosine_hnsw`]
    /// but over the structural-embedding space (`struct_vec`) with hyperbolic
    /// distance. Builds the Poincaré index lazily on first call; rebuilds on
    /// any mutation.
    pub fn search_poincare_hnsw(&mut self, query: &[f32], top_k: usize) -> Vec<(String, f32)> {
        if self.entries.is_empty() {
            return Vec::new();
        }
        if self.poincare_index.is_none() {
            let points: Vec<(String, Vec<f32>)> = self
                .entries
                .iter()
                .map(|(iri, e)| (iri.clone(), e.struct_vec.clone()))
                .collect();
            self.poincare_index = Some(PoincareIndex::build(points));
        }
        match self.poincare_index.as_mut() {
            Some(idx) => idx.search(query, top_k),
            None => Vec::new(),
        }
    }

    pub fn search_product(
        &self,
        text_query: &[f32],
        struct_query: &[f32],
        top_k: usize,
        alpha: f32,
    ) -> Vec<(String, f32)> {
        let text_norm = l2_normalize(text_query);
        let mut scores: Vec<(String, f32)> = self.entries.iter()
            .map(|(iri, e)| {
                let cos = cosine_similarity(&text_norm, &e.text_vec);
                let poinc = poincare_distance(struct_query, &e.struct_vec);
                let poinc_sim = 1.0 / (1.0 + poinc);
                let combined = alpha * cos + (1.0 - alpha) * poinc_sim;
                (iri.clone(), combined)
            })
            .collect();
        scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
        scores.truncate(top_k);
        scores
    }

    /// Deterministic FNV-1a 64-bit fingerprint of the entry set. Stable across
    /// processes; used to detect when a cached HNSW index is stale because the
    /// underlying vectors have changed. Includes both keys and text-vec bytes
    /// in the hash so re-embedding the same IRI with a new vector triggers a
    /// rebuild.
    fn entries_fingerprint(&self) -> Vec<u8> {
        let mut keys: Vec<&String> = self.entries.keys().collect();
        keys.sort();
        let mut hash: u64 = 0xcbf29ce484222325;
        for k in keys {
            for byte in k.as_bytes() {
                hash ^= *byte as u64;
                hash = hash.wrapping_mul(0x100000001b3);
            }
            let v = &self.entries[k];
            for f in &v.text_vec {
                for byte in f.to_le_bytes() {
                    hash ^= byte as u64;
                    hash = hash.wrapping_mul(0x100000001b3);
                }
            }
        }
        hash.to_le_bytes().to_vec()
    }

    /// Force-rebuild the HNSW cosine index using explicit HNSW parameters.
    /// Drops any previously-built index. The new index is held in memory; call
    /// [`Self::persist_cosine_index`] to save it.
    pub fn rebuild_cosine_index(&mut self, params: crate::hnsw_index::BuildParams) {
        if self.entries.is_empty() {
            self.cosine_index = None;
            return;
        }
        let points: Vec<(String, Vec<f32>)> = self
            .entries
            .iter()
            .map(|(iri, e)| (iri.clone(), e.text_vec.clone()))
            .collect();
        self.cosine_index = Some(crate::hnsw_index::CosineIndex::build_with_params(
            points, params,
        ));
    }

    /// Force-rebuild the HNSW Poincaré index using explicit HNSW parameters.
    /// Same semantics as [`Self::rebuild_cosine_index`] but for the
    /// structural-embedding space.
    pub fn rebuild_poincare_index(&mut self, params: crate::hnsw_index::BuildParams) {
        if self.entries.is_empty() {
            self.poincare_index = None;
            return;
        }
        let points: Vec<(String, Vec<f32>)> = self
            .entries
            .iter()
            .map(|(iri, e)| (iri.clone(), e.struct_vec.clone()))
            .collect();
        self.poincare_index = Some(crate::hnsw_index::PoincareIndex::build_with_params(
            points, params,
        ));
    }

    /// Persist the current HNSW cosine index to SQLite (table `hnsw_index_cache`).
    /// Builds the index first if it isn't built. Subsequent `load_cosine_index()`
    /// calls (e.g. at process startup via `load_from_db`) read it back and skip
    /// the rebuild as long as the entry fingerprint matches.
    pub fn persist_cosine_index(&mut self) -> anyhow::Result<()> {
        if self.entries.is_empty() {
            return Ok(());
        }
        if self.cosine_index.is_none() {
            let points: Vec<(String, Vec<f32>)> = self
                .entries
                .iter()
                .map(|(iri, e)| (iri.clone(), e.text_vec.clone()))
                .collect();
            self.cosine_index = Some(CosineIndex::build(points));
        }
        let bytes = match self.cosine_index.as_ref() {
            Some(idx) => idx.to_bytes()?,
            None => return Ok(()),
        };
        let fp = self.entries_fingerprint();
        let count = self.entries.len() as i64;
        let conn = self.db.conn();
        conn.execute(
            "INSERT OR REPLACE INTO hnsw_index_cache (kind, entries_hash, entry_count, serialised) \
             VALUES ('cosine', ?1, ?2, ?3)",
            rusqlite::params![fp, count, bytes],
        )?;
        Ok(())
    }

    /// Try to load a previously-persisted HNSW cosine index. If the stored
    /// fingerprint matches the current entries' fingerprint, the index is
    /// deserialised in-place and subsequent `search_cosine_hnsw` calls skip
    /// the rebuild. If the fingerprint mismatches (or no cache exists), this
    /// is a no-op and the next `search_cosine_hnsw` rebuilds normally.
    pub fn load_cosine_index(&mut self) -> anyhow::Result<bool> {
        let conn = self.db.conn();
        let row: Option<(Vec<u8>, Vec<u8>)> = conn
            .query_row(
                "SELECT entries_hash, serialised FROM hnsw_index_cache WHERE kind = 'cosine'",
                [],
                |row| Ok((row.get::<_, Vec<u8>>(0)?, row.get::<_, Vec<u8>>(1)?)),
            )
            .ok();
        let (stored_hash, bytes) = match row {
            Some(x) => x,
            None => return Ok(false),
        };
        let current_hash = self.entries_fingerprint();
        if stored_hash != current_hash {
            // Stale — let the rebuild path handle it next time.
            return Ok(false);
        }
        self.cosine_index = Some(CosineIndex::from_bytes(&bytes)?);
        Ok(true)
    }

    /// Async background flush of the cosine index. Serialises the index
    /// synchronously (in-memory bincode work, typically < 100ms for ontologies
    /// under ~10k classes), then dispatches the SQLite write to a tokio
    /// `spawn_blocking` task. Returns a JoinHandle so the caller can await
    /// completion if they care; otherwise fire-and-forget is fine.
    ///
    /// Use when persisting from inside an async MCP tool handler over a
    /// large index, where the SQLite write latency would otherwise hold up
    /// the handler thread. For small indices the sync `persist_cosine_index`
    /// is just as fast.
    pub fn persist_cosine_index_async(
        &mut self,
    ) -> anyhow::Result<tokio::task::JoinHandle<anyhow::Result<()>>> {
        if self.entries.is_empty() {
            return Ok(tokio::task::spawn(async { Ok::<(), anyhow::Error>(()) }));
        }
        if self.cosine_index.is_none() {
            let points: Vec<(String, Vec<f32>)> = self
                .entries
                .iter()
                .map(|(iri, e)| (iri.clone(), e.text_vec.clone()))
                .collect();
            self.cosine_index = Some(CosineIndex::build(points));
        }
        let bytes = self
            .cosine_index
            .as_ref()
            .expect("cosine index just built or pre-existing")
            .to_bytes()?;
        let fp = self.entries_fingerprint();
        let count = self.entries.len() as i64;
        let db = self.db.clone();
        let handle = tokio::task::spawn_blocking(move || {
            let conn = db.conn();
            conn.execute(
                "INSERT OR REPLACE INTO hnsw_index_cache (kind, entries_hash, entry_count, serialised) \
                 VALUES ('cosine', ?1, ?2, ?3)",
                rusqlite::params![fp, count, bytes],
            )?;
            Ok::<(), anyhow::Error>(())
        });
        Ok(handle)
    }

    /// Async background flush of the Poincaré index. See
    /// [`Self::persist_cosine_index_async`] for semantics.
    pub fn persist_poincare_index_async(
        &mut self,
    ) -> anyhow::Result<tokio::task::JoinHandle<anyhow::Result<()>>> {
        if self.entries.is_empty() {
            return Ok(tokio::task::spawn(async { Ok::<(), anyhow::Error>(()) }));
        }
        if self.poincare_index.is_none() {
            let points: Vec<(String, Vec<f32>)> = self
                .entries
                .iter()
                .map(|(iri, e)| (iri.clone(), e.struct_vec.clone()))
                .collect();
            self.poincare_index = Some(PoincareIndex::build(points));
        }
        let bytes = self
            .poincare_index
            .as_ref()
            .expect("poincare index just built or pre-existing")
            .to_bytes()?;
        let fp = self.entries_fingerprint();
        let count = self.entries.len() as i64;
        let db = self.db.clone();
        let handle = tokio::task::spawn_blocking(move || {
            let conn = db.conn();
            conn.execute(
                "INSERT OR REPLACE INTO hnsw_index_cache (kind, entries_hash, entry_count, serialised) \
                 VALUES ('poincare', ?1, ?2, ?3)",
                rusqlite::params![fp, count, bytes],
            )?;
            Ok::<(), anyhow::Error>(())
        });
        Ok(handle)
    }

    /// Persist the Poincaré index. Mirrors [`Self::persist_cosine_index`] but
    /// uses `kind = 'poincare'` in the cache row. Both indices use the SAME
    /// entries fingerprint (the entry set is identical; only the index over
    /// it differs) so a single fingerprint mismatch invalidates both kinds.
    pub fn persist_poincare_index(&mut self) -> anyhow::Result<()> {
        if self.entries.is_empty() {
            return Ok(());
        }
        if self.poincare_index.is_none() {
            let points: Vec<(String, Vec<f32>)> = self
                .entries
                .iter()
                .map(|(iri, e)| (iri.clone(), e.struct_vec.clone()))
                .collect();
            self.poincare_index = Some(PoincareIndex::build(points));
        }
        let bytes = match self.poincare_index.as_ref() {
            Some(idx) => idx.to_bytes()?,
            None => return Ok(()),
        };
        let fp = self.entries_fingerprint();
        let count = self.entries.len() as i64;
        let conn = self.db.conn();
        conn.execute(
            "INSERT OR REPLACE INTO hnsw_index_cache (kind, entries_hash, entry_count, serialised) \
             VALUES ('poincare', ?1, ?2, ?3)",
            rusqlite::params![fp, count, bytes],
        )?;
        Ok(())
    }

    /// Try to load a persisted Poincaré index. Same fingerprint-validation as
    /// [`Self::load_cosine_index`].
    pub fn load_poincare_index(&mut self) -> anyhow::Result<bool> {
        let conn = self.db.conn();
        let row: Option<(Vec<u8>, Vec<u8>)> = conn
            .query_row(
                "SELECT entries_hash, serialised FROM hnsw_index_cache WHERE kind = 'poincare'",
                [],
                |row| Ok((row.get::<_, Vec<u8>>(0)?, row.get::<_, Vec<u8>>(1)?)),
            )
            .ok();
        let (stored_hash, bytes) = match row {
            Some(x) => x,
            None => return Ok(false),
        };
        let current_hash = self.entries_fingerprint();
        if stored_hash != current_hash {
            return Ok(false);
        }
        self.poincare_index = Some(PoincareIndex::from_bytes(&bytes)?);
        Ok(true)
    }

    pub fn persist(&self) -> anyhow::Result<()> {
        let conn = self.db.conn();
        let tx = conn.unchecked_transaction()?;
        tx.execute("DELETE FROM embeddings", [])?;
        {
            let mut stmt = tx.prepare(
                "INSERT INTO embeddings (iri, text_vec, struct_vec, text_dim, struct_dim) VALUES (?1, ?2, ?3, ?4, ?5)"
            )?;
            for (iri, entry) in &self.entries {
                let text_bytes = f32_slice_to_bytes(&entry.text_vec);
                let struct_bytes = f32_slice_to_bytes(&entry.struct_vec);
                stmt.execute(rusqlite::params![
                    iri,
                    text_bytes,
                    struct_bytes,
                    entry.text_vec.len() as i64,
                    entry.struct_vec.len() as i64,
                ])?;
            }
        }
        tx.commit()?;
        Ok(())
    }

    pub fn load_from_db(&mut self) -> anyhow::Result<()> {
        // Scope the connection + statement so the conn MutexGuard is dropped
        // before we call `load_cosine_index` (which re-acquires it).
        {
            let conn = self.db.conn();
            let mut stmt = conn.prepare("SELECT iri, text_vec, struct_vec FROM embeddings")?;
            let rows = stmt.query_map([], |row| {
                let iri: String = row.get(0)?;
                let text_bytes: Vec<u8> = row.get(1)?;
                let struct_bytes: Vec<u8> = row.get(2)?;
                Ok((iri, text_bytes, struct_bytes))
            })?;

            for row in rows {
                let (iri, text_bytes, struct_bytes) = row?;
                self.entries.insert(iri, VecEntry {
                    text_vec: bytes_to_f32_vec(&text_bytes),
                    struct_vec: bytes_to_f32_vec(&struct_bytes),
                });
            }
        }
        // Invalidate any previously-built HNSW indices; try to load persisted
        // ones. If the persisted fingerprint matches the entries we just loaded,
        // the next `search_cosine_hnsw` / `search_poincare_hnsw` skips rebuild.
        self.cosine_index = None;
        self.poincare_index = None;
        let _ = self.load_cosine_index()?;
        let _ = self.load_poincare_index()?;
        Ok(())
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn get_text_vec(&self, iri: &str) -> Option<&[f32]> {
        self.entries.get(iri).map(|e| e.text_vec.as_slice())
    }

    pub fn get_struct_vec(&self, iri: &str) -> Option<&[f32]> {
        self.entries.get(iri).map(|e| e.struct_vec.as_slice())
    }
}

fn f32_slice_to_bytes(v: &[f32]) -> Vec<u8> {
    v.iter().flat_map(|f| f.to_le_bytes()).collect()
}

fn bytes_to_f32_vec(b: &[u8]) -> Vec<f32> {
    b.chunks_exact(4)
        .map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]]))
        .collect()
}
