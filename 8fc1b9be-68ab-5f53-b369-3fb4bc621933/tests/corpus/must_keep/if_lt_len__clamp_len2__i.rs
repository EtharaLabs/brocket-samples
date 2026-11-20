// GENERATED. axis combination: if_lt_len__clamp_len2__i
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    let base = i;
    if base < s.len() {
        let idx = base.clamp(1, s.len() - 2);
        return s[idx];
    }
    0
}
