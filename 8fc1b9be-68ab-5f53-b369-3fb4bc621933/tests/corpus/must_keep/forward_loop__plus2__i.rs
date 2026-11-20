// GENERATED. axis combination: forward_loop__plus2__i
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    let mut total = 0;
    for base in 0..s.len() {
        let idx = base + 2;
        total += s[idx];
    }
    total
}
