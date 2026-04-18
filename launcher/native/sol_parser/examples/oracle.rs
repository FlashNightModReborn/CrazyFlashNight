//! Phase A Layer 1 oracle: soData top-level key assertions + basic structure
//! probe + JSON dump to disk for Layer 2 use.
//!
//! Usage: cargo run --release --example oracle -- <sol-path> [out-json-path]
//!
//! Exit code 0 = all Layer 1 checks passed; nonzero otherwise.

use std::env;
use std::fs;
use std::path::Path;
use std::process::ExitCode;

use serde_json::Value;

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: oracle <sol-path> [out-json-path]");
        return ExitCode::from(2);
    }
    let sol_path = Path::new(&args[1]);
    let out_json = args.get(2).cloned();

    let sol_data = match sol_parser::parse_sol_path(sol_path) {
        Ok(v) => v,
        Err(rc) => {
            eprintln!("[FAIL] parse_sol_path returned rc={}", rc);
            return ExitCode::from(1);
        }
    };
    println!("[INFO] parsed {} (top-level key count = {})",
        sol_path.display(),
        sol_data.as_object().map(|m| m.len()).unwrap_or(0));

    let mut fail = 0u32;

    // ── Layer 1.1: top-level presence ──
    let required_top = ["test", "tasks_to_do", "\u{6218}\u{5BA0}",
        "\u{5546}\u{57CE}\u{5DF2}\u{8D2D}\u{4E70}\u{7269}\u{54C1}"];
    for key in required_top.iter() {
        let present = sol_data.get(key).is_some();
        let mark = if present { "OK     " } else { "MISSING" };
        println!("  L1.1 {} top-level[{}]", mark, key);
        if !present { fail += 1; }
    }

    // ── Layer 1.2: soData.test is Object and has version ──
    let test = sol_data.get("test");
    if let Some(test_v) = test {
        if test_v.is_object() {
            println!("  L1.2 OK      soData.test is Object");
        } else {
            println!("  L1.2 FAIL    soData.test is {:?}, expected Object", short_type(test_v));
            fail += 1;
        }
        let version = test_v.get("version");
        match version {
            Some(Value::String(s)) => println!("  L1.2 OK      soData.test.version = {:?}", s),
            other => {
                println!("  L1.2 FAIL    soData.test.version missing or wrong type: {:?}", other);
                fail += 1;
            }
        }
        // mydata[0] is character Array (len_attr>0 ECMAArray → JArray);
        // mydata[0][0] = name, [0][3] = level.
        let a0 = test_v.get("0");
        match a0 {
            Some(Value::Array(arr)) => {
                let name = arr.get(0);
                let level = arr.get(3);
                if let Some(Value::String(n)) = name {
                    println!("  L1.2 OK      soData.test[0][0] (name) = {:?}", n);
                } else {
                    println!("  L1.2 FAIL    soData.test[0][0] not a String: {:?}", short_type_opt(name));
                    fail += 1;
                }
                if let Some(Value::Number(n)) = level {
                    println!("  L1.2 OK      soData.test[0][3] (level) = {}", n);
                } else {
                    println!("  L1.2 FAIL    soData.test[0][3] not a Number: {:?}", short_type_opt(level));
                    fail += 1;
                }
                if arr.len() < 14 {
                    println!("  L1.2 FAIL    soData.test[0] len {} < 14 (validateMydata requires >=14)", arr.len());
                    fail += 1;
                } else {
                    println!("  L1.2 OK      soData.test[0] len = {}", arr.len());
                }
            }
            Some(other) => {
                println!("  L1.2 FAIL    soData.test[0] is {:?}, expected Array (AS2 character array)", short_type(other));
                fail += 1;
            }
            None => {
                println!("  L1.2 FAIL    soData.test[0] missing");
                fail += 1;
            }
        }
    } else {
        println!("  L1.2 FAIL    soData.test missing entirely");
        fail += 1;
    }

    // ── Layer 1.3: AMF0 undefined/null/missing are all distinguishable downstream ──
    // We don't have fabricated fixtures here but we check that the real SOL
    // doesn't have any `Value::Null` leakage into unexpected nested slots.
    let null_count = count_nulls(&sol_data);
    println!("  L1.3 INFO    total JSON null leaves in tree: {}", null_count);

    // ── Write out JSON for Layer 2 diff ──
    if let Some(out) = out_json {
        match serde_json::to_string_pretty(&sol_data) {
            Ok(s) => {
                match fs::write(&out, s) {
                    Ok(_) => println!("[OUT] wrote JSON to {}", out),
                    Err(e) => println!("[WARN] failed to write {}: {}", out, e),
                }
            }
            Err(e) => println!("[WARN] serialize for output: {}", e),
        }
    }

    if fail == 0 {
        println!("[PASS] Layer 1 oracle: all assertions satisfied");
        ExitCode::from(0)
    } else {
        println!("[FAIL] Layer 1 oracle: {} assertion(s) failed", fail);
        ExitCode::from(1)
    }
}

fn short_type(v: &Value) -> &'static str {
    match v {
        Value::Null => "Null",
        Value::Bool(_) => "Bool",
        Value::Number(_) => "Number",
        Value::String(_) => "String",
        Value::Array(_) => "Array",
        Value::Object(_) => "Object",
    }
}

fn short_type_opt(v: Option<&Value>) -> &'static str {
    match v {
        None => "Missing",
        Some(v) => short_type(v),
    }
}

fn count_nulls(v: &Value) -> u64 {
    match v {
        Value::Null => 1,
        Value::Array(a) => a.iter().map(count_nulls).sum(),
        Value::Object(m) => m.values().map(count_nulls).sum(),
        _ => 0,
    }
}
