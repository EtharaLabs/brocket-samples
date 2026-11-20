// GENERATED. axis combination: forward_loop__min_other__i
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    let mut total = 0;
    for base in 0..s.len() {
        let idx = base.min(j);
        total += s[idx];
    }
    total
}
