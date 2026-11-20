// GENERATED. axis combination: reverse_loop__direct__i
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    let mut total = 0;
    for base in (0..s.len()).rev() {
        let idx = base;
        total += s[idx];
    }
    total
}
