// Times the Rust `regex` crate over the corpus. Two configurations: bytes with Unicode off (ASCII \w \d \s \b, like RE2 and AemiRegex)
// and str with Unicode on (the crate's default). Output: engine,workload,median_ms,count
use regex::bytes::RegexBuilder as BytesBuilder;
use regex::RegexBuilder;
use std::time::Instant;

fn walk(dir: &std::path::Path, out: &mut Vec<std::path::PathBuf>) {
    if let Ok(entries) = std::fs::read_dir(dir) {
        for e in entries.flatten() {
            let p = e.path();
            if p.is_dir() { walk(&p, out) } else if p.extension().map_or(false, |x| x == "swift") { out.push(p) }
        }
    }
}

fn median(mut v: Vec<f64>) -> f64 {
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    v[v.len() / 2]
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut paths = Vec::new();
    walk(std::path::Path::new(&args[2]), &mut paths);
    paths.sort();
    let mut bytes: Vec<Vec<u8>> = paths.iter().map(|p| std::fs::read(p).unwrap()).collect();
    if std::env::var("CONCAT").is_ok() {
        // one buffer: measures scan speed without per-call overhead
        bytes = vec![bytes.concat()];
    }
    let strings: Vec<String> = bytes.iter().map(|b| String::from_utf8_lossy(b).into_owned()).collect();
    for line in std::fs::read_to_string(&args[1]).unwrap().lines() {
        let (name, pattern) = line.split_once('\t').unwrap();
        let re = BytesBuilder::new(pattern).unicode(false).build().unwrap();
        let (mut times, mut count) = (Vec::new(), 0);
        for _ in 0..9 {
            let t = Instant::now();
            count = bytes.iter().map(|b| re.find_iter(b).count()).sum::<usize>();
            times.push(t.elapsed().as_secs_f64() * 1e3);
        }
        println!("Rust regex (ASCII bytes),{},{:.2},{}", name, median(times), count);
        let re = RegexBuilder::new(pattern).build().unwrap();
        let (mut times, mut count) = (Vec::new(), 0);
        for _ in 0..9 {
            let t = Instant::now();
            count = strings.iter().map(|s| re.find_iter(s).count()).sum::<usize>();
            times.push(t.elapsed().as_secs_f64() * 1e3);
        }
        println!("Rust regex (Unicode str),{},{:.2},{}", name, median(times), count);
    }
}
