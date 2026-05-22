use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: dumpidx <sol-path> [first N to show] [around INDEX +/- 3]");
        std::process::exit(2);
    }
    let bytes = fs::read(&args[1]).expect("read");
    let show_n: usize = args
        .get(2)
        .and_then(|s| s.parse().ok())
        .unwrap_or(30);
    let around: Option<usize> = args.get(3).and_then(|s| s.parse().ok());

    let idx = sol_parser::debug_index(&bytes).expect("parse");
    println!("total by_index entries: {}", idx.len());
    println!();

    if let Some(c) = around {
        let lo = c.saturating_sub(3);
        let hi = (c + 4).min(idx.len());
        println!("-- around index {}:", c);
        for i in lo..hi {
            let (n, tag, prev) = &idx[i];
            let marker = if i == c { " <-- target" } else { "" };
            println!("  [{:4}] {:10}  {}{}", n, tag, prev, marker);
        }
        println!();
    }

    println!("-- first {} entries:", show_n.min(idx.len()));
    for (n, tag, prev) in idx.iter().take(show_n) {
        println!("  [{:4}] {:10}  {}", n, tag, prev);
    }
}
