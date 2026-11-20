// GENERATED. axis combination: if_lt_len__mod_len__j
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    let base = j;
    if base < s.len() {
        let idx = base % s.len();
        return s[idx];
    }
    0
}
