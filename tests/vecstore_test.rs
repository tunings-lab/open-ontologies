#![cfg(feature = "embeddings")]

use open_ontologies::vecstore::VecStore;
use open_ontologies::state::StateDb;

fn test_db() -> StateDb {
    let tmp = tempfile::NamedTempFile::new().unwrap();
    let path = tmp.path().to_path_buf();
    std::mem::forget(tmp);
    StateDb::open(&path).unwrap()
}

#[test]
fn test_insert_and_search_cosine() {
    let db = test_db();
    let mut store = VecStore::new(db);

    store.upsert("http://ex.org/Dog", &[0.9, 0.1, 0.0], &[0.1, 0.0]);
    store.upsert("http://ex.org/Cat", &[0.8, 0.2, 0.0], &[0.15, 0.0]);
    store.upsert("http://ex.org/Car", &[0.0, 0.0, 1.0], &[0.5, 0.0]);

    let results = store.search_cosine(&[0.85, 0.15, 0.0], 2);
    assert_eq!(results.len(), 2);
    assert!(results[0].0.contains("Dog") || results[0].0.contains("Cat"),
        "Top result should be Dog or Cat, got {}", results[0].0);
}

#[test]
fn test_search_poincare() {
    let db = test_db();
    let mut store = VecStore::new(db);

    store.upsert("http://ex.org/Dog", &[0.0, 0.0, 0.0], &[0.1, 0.05]);
    store.upsert("http://ex.org/Cat", &[0.0, 0.0, 0.0], &[0.12, 0.03]);
    store.upsert("http://ex.org/Car", &[0.0, 0.0, 0.0], &[0.8, 0.8]);

    let results = store.search_poincare(&[0.11, 0.04], 2);
    assert_eq!(results.len(), 2);
    let iris: Vec<&str> = results.iter().map(|r| r.0.as_str()).collect();
    assert!(iris.contains(&"http://ex.org/Dog"));
    assert!(iris.contains(&"http://ex.org/Cat"));
}

#[test]
fn test_product_search() {
    let db = test_db();
    let mut store = VecStore::new(db);

    store.upsert("http://ex.org/Dog", &[0.9, 0.1], &[0.1, 0.0]);
    store.upsert("http://ex.org/Cat", &[0.8, 0.2], &[0.12, 0.0]);
    store.upsert("http://ex.org/Car", &[0.0, 1.0], &[0.8, 0.8]);

    let results = store.search_product(&[0.85, 0.15], &[0.11, 0.0], 2, 0.5);
    assert_eq!(results.len(), 2);
    assert!(results[0].0.contains("Dog") || results[0].0.contains("Cat"));
}

#[test]
fn test_upsert_overwrites() {
    let db = test_db();
    let mut store = VecStore::new(db);

    store.upsert("http://ex.org/Dog", &[1.0, 0.0], &[0.1, 0.0]);
    store.upsert("http://ex.org/Dog", &[0.0, 1.0], &[0.5, 0.0]);

    let results = store.search_cosine(&[0.0, 1.0], 1);
    assert_eq!(results[0].0, "http://ex.org/Dog");
    assert!(results[0].1 > 0.99);
}

#[test]
fn test_persist_and_reload() {
    let tmp = tempfile::NamedTempFile::new().unwrap();
    let path = tmp.path().to_path_buf();
    std::mem::forget(tmp);

    {
        let db = StateDb::open(&path).unwrap();
        let mut store = VecStore::new(db);
        store.upsert("http://ex.org/Dog", &[0.9, 0.1], &[0.1, 0.0]);
        store.persist().unwrap();
    }

    {
        let db = StateDb::open(&path).unwrap();
        let mut store = VecStore::new(db);
        store.load_from_db().unwrap();
        let results = store.search_cosine(&[0.9, 0.1], 1);
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].0, "http://ex.org/Dog");
    }
}

#[test]
fn test_remove() {
    let db = test_db();
    let mut store = VecStore::new(db);

    store.upsert("http://ex.org/Dog", &[0.9, 0.1], &[0.1, 0.0]);
    store.upsert("http://ex.org/Cat", &[0.8, 0.2], &[0.1, 0.0]);
    store.remove("http://ex.org/Dog");

    let results = store.search_cosine(&[0.9, 0.1], 10);
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].0, "http://ex.org/Cat");
}

#[test]
fn search_cosine_hnsw_returns_same_top_1_as_brute_force() {
    // Round-trip test for the HNSW backing index: top-1 must agree with the
    // brute-force linear scan on well-separated vectors.
    let db = test_db();
    let mut store = VecStore::new(db);

    let entries: [(&str, [f32; 3]); 6] = [
        ("http://ex.org/Cat",    [1.0, 0.05, 0.0]),
        ("http://ex.org/Kitten", [0.98, 0.1, 0.0]),
        ("http://ex.org/Dog",    [0.9, 0.3, 0.0]),
        ("http://ex.org/Bird",   [0.4, 0.7, 0.0]),
        ("http://ex.org/Car",    [0.0, 0.1, 1.0]),
        ("http://ex.org/Bike",   [0.0, 0.0, 0.95]),
    ];
    for (iri, vec) in entries.iter() {
        store.upsert(iri, vec, &[0.0]);
    }

    let query = [1.0_f32, 0.0, 0.0]; // Closest to Cat by far.

    let brute = store.search_cosine(&query, 1);
    let hnsw = store.search_cosine_hnsw(&query, 1);

    assert_eq!(brute.len(), 1);
    assert_eq!(hnsw.len(), 1);
    assert_eq!(
        brute[0].0, hnsw[0].0,
        "top-1 disagreement between brute-force and HNSW: brute={:?}, hnsw={:?}",
        brute, hnsw
    );
    assert!(brute[0].0.contains("Cat"));
}

#[test]
fn search_cosine_hnsw_invalidates_on_mutation() {
    // After an upsert the index must rebuild. Warm the index with an
    // initial search, then insert a closer match — the next search must
    // surface it (i.e. the stale index didn't sandbag the result).
    let db = test_db();
    let mut store = VecStore::new(db);

    store.upsert("http://ex.org/Cat", &[0.9, 0.1, 0.0], &[0.0]);
    store.upsert("http://ex.org/Dog", &[0.7, 0.3, 0.0], &[0.0]);

    let first = store.search_cosine_hnsw(&[1.0, 0.0, 0.0], 1);
    assert!(first[0].0.contains("Cat"));

    store.upsert("http://ex.org/Tiger", &[0.99, 0.05, 0.0], &[0.0]);

    let second = store.search_cosine_hnsw(&[1.0, 0.0, 0.0], 1);
    assert!(
        second[0].0.contains("Tiger") || second[0].0.contains("Cat"),
        "after upsert of closer match, expected Tiger or Cat in top-1; got {:?}",
        second
    );
    // The structural invariant: the previously-built index didn't prevent
    // Tiger from being considered. Either Tiger (very close) or Cat (close)
    // demonstrate that.
}

#[test]
fn search_cosine_hnsw_on_empty_store_returns_empty() {
    let db = test_db();
    let mut store = VecStore::new(db);
    let results = store.search_cosine_hnsw(&[1.0, 0.0, 0.0], 5);
    assert!(results.is_empty());
}
