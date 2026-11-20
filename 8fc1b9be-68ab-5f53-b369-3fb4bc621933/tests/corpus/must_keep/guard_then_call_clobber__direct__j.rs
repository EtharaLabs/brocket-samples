// GENERATED. axis combination: guard_then_call_clobber__direct__j
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    let mut base = j;
    if base < s.len() {
        base = j.max(s.len());
        let idx = base;
        return s[idx];
    }
    0
}
