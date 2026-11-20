// GENERATED. axis combination: forward_loop__max_len1__i
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    let mut total = 0;
    for base in 0..s.len() {
        let idx = base.max(s.len() - 1);
        total += s[idx];
    }
    total
}
