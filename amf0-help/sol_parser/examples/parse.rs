use std::env;
fn main() {
    let args: Vec<String> = env::args().collect();
    let bytes = std::fs::read(&args[1]).expect("read");
    match sol_parser::parse_sol_bytes(&bytes) {
        Ok(j) => println!("{}", serde_json::to_string_pretty(&j).unwrap()),
        Err(rc) => println!("parse error rc={}", rc),
    }
}
