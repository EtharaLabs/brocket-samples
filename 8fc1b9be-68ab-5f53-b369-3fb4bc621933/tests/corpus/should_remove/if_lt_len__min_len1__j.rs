// GENERATED. axis combination: if_lt_len__min_len1__j
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    let base = j;
    if base < s.len() {
        let idx = base.min(s.len() - 1);
        return s[idx];
    }
    0
}
