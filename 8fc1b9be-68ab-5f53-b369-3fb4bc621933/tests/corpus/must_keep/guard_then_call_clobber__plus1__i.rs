// GENERATED. axis combination: guard_then_call_clobber__plus1__i
pub fn f(s: &[u32], i: usize, j: usize, t: &[u32]) -> u32 {
    let mut base = i;
    if base < s.len() {
        base = j.max(s.len());
        let idx = base + 1;
        return s[idx];
    }
    0
}
