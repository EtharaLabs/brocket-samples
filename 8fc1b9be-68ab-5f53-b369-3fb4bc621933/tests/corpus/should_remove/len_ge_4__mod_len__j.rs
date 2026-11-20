// GENERATED. axis combination: len_ge_4__mod_len__j
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    if s.len() < 4 {
        return 0;
    }
    let base = j;
    let idx = base % s.len();
    s[idx]
}
