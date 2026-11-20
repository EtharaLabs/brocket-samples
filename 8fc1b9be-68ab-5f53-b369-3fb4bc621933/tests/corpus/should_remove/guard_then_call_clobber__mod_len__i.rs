// GENERATED. axis combination: guard_then_call_clobber__mod_len__i
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    let mut base = i;
    if base < s.len() {
        base = j.max(s.len());
        let idx = base % s.len();
        return s[idx];
    }
    0
}
