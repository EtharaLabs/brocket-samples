// GENERATED. axis combination: if_lt_len__min_other__i
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    let base = i;
    if base < s.len() {
        let idx = base.min(j);
        return s[idx];
    }
    0
}
