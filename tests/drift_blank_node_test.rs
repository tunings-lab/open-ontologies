use open_ontologies::drift::DriftDetector;
use open_ontologies::state::StateDb;
use tempfile::NamedTempFile;

fn setup() -> StateDb {
    let tmp = NamedTempFile::new().unwrap();
    let path = tmp.path().to_path_buf();
    std::mem::forget(tmp);
    StateDb::open(&path).unwrap()
}

const PIZZA_WITH_RESTRICTION: &str = r#"
    @prefix owl:  <http://www.w3.org/2002/07/owl#> .
    @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
    @prefix ex:   <http://example.org/> .

    ex:Pizza      a owl:Class .
    ex:Topping    a owl:Class .
    ex:hasTopping a owl:ObjectProperty .

    ex:MeatyPizza a owl:Class ;
        owl:equivalentClass [
            a owl:Class ;
            owl:intersectionOf (
                ex:Pizza
                [ a owl:Restriction ;
                  owl:onProperty     ex:hasTopping ;
                  owl:someValuesFrom ex:Topping ]
            )
        ] .
"#;

#[test]
fn drift_of_same_ontology_with_restrictions_returns_no_changes() {
    let db = setup();
    let detector = DriftDetector::new(db);

    let result = detector.detect(PIZZA_WITH_RESTRICTION, PIZZA_WITH_RESTRICTION).unwrap();
    let parsed: serde_json::Value = serde_json::from_str(&result).unwrap();

    let added    = parsed["added"].as_array().unwrap();
    let removed  = parsed["removed"].as_array().unwrap();
    let renames  = parsed["likely_renames"].as_array().unwrap();
    let velocity = parsed["drift_velocity"].as_f64().unwrap();

    assert!(
        added.is_empty() && removed.is_empty() && renames.is_empty() && velocity < 0.01,
        "expected zero drift between two snapshots of the same ontology; got \
         added={:?}, removed={:?}, renames={:?}, velocity={}",
        added, removed, renames, velocity
    );
}

#[test]
fn drift_vocabulary_excludes_blank_node_iris() {
    let db = setup();
    let detector = DriftDetector::new(db);

    let v2 = r#"
        @prefix owl:  <http://www.w3.org/2002/07/owl#> .
        @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
        @prefix ex:   <http://example.org/> .

        ex:Pizza      a owl:Class .
        ex:Topping    a owl:Class .
        ex:hasTopping a owl:ObjectProperty .
        ex:VeggiePizza a owl:Class ;
            owl:equivalentClass [
                a owl:Class ;
                owl:intersectionOf (
                    ex:Pizza
                    [ a owl:Restriction ;
                      owl:onProperty     ex:hasTopping ;
                      owl:someValuesFrom ex:Topping ]
                )
            ] .
    "#;

    let result = detector.detect(PIZZA_WITH_RESTRICTION, v2).unwrap();
    let parsed: serde_json::Value = serde_json::from_str(&result).unwrap();

    for iri in parsed["added"].as_array().unwrap().iter()
        .chain(parsed["removed"].as_array().unwrap().iter())
    {
        let s = iri.as_str().unwrap();
        assert!(
            !s.starts_with("_:"),
            "drift report leaked a blank-node IRI into named-vocabulary diff: {}", s
        );
    }

    assert!(
        parsed["removed"].as_array().unwrap().iter()
            .any(|v| v.as_str().unwrap().contains("MeatyPizza")),
        "real removal (MeatyPizza) should still be detected"
    );
    assert!(
        parsed["added"].as_array().unwrap().iter()
            .any(|v| v.as_str().unwrap().contains("VeggiePizza")),
        "real addition (VeggiePizza) should still be detected"
    );
}
